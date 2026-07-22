package main

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"time"
)

// ---------- group schema ----------

func (db *DB) migrateGroups() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS groups (
			id         TEXT PRIMARY KEY,
			name       TEXT NOT NULL,
			owner_id   INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS group_members (
			group_id   TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			account_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			role       TEXT NOT NULL DEFAULT 'member',
			joined_at  TEXT NOT NULL,
			PRIMARY KEY (group_id, account_id)
		)`,
		`CREATE TABLE IF NOT EXISTS group_invites (
			group_id   TEXT NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
			invitee_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			inviter_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			created_at TEXT NOT NULL,
			PRIMARY KEY (group_id, invitee_id)
		)`,
	}
	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return err
		}
	}
	return nil
}

// ---------- group API types ----------

type groupMember struct {
	NumericID uint64 `json:"numeric_id"`
	Username  string `json:"username"`
	Role      string `json:"role"`
}

type groupInfo struct {
	ID      string        `json:"id"`
	Name    string        `json:"name"`
	OwnerID uint64        `json:"owner_id"`
	Members []groupMember `json:"members"`
}

// ---------- helpers ----------

func (db *DB) roleInGroup(ctx context.Context, groupID string, accountID int64) (string, bool) {
	var role string
	err := db.QueryRowContext(ctx,
		`SELECT role FROM group_members WHERE group_id = ? AND account_id = ?`,
		groupID, accountID).Scan(&role)
	if err != nil {
		return "", false
	}
	return role, true
}

func (db *DB) groupMembers(ctx context.Context, groupID string) ([]groupMember, []int64, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT a.numeric_id, COALESCE(a.username, ''), m.role, a.id
		 FROM group_members m JOIN accounts a ON a.id = m.account_id
		 WHERE m.group_id = ?
		 ORDER BY CASE m.role WHEN 'owner' THEN 0 WHEN 'admin' THEN 1 ELSE 2 END,
		          m.joined_at ASC`, groupID)
	if err != nil {
		return nil, nil, err
	}
	defer rows.Close()
	var members []groupMember
	var ids []int64
	for rows.Next() {
		var m groupMember
		var id int64
		if err := rows.Scan(&m.NumericID, &m.Username, &m.Role, &id); err != nil {
			return nil, nil, err
		}
		members = append(members, m)
		ids = append(ids, id)
	}
	return members, ids, nil
}

func (db *DB) groupInfo(ctx context.Context, groupID string) (*groupInfo, error) {
	var g groupInfo
	var ownerRow int64
	err := db.QueryRowContext(ctx,
		`SELECT g.id, g.name, a.numeric_id, g.owner_id
		 FROM groups g JOIN accounts a ON a.id = g.owner_id
		 WHERE g.id = ?`, groupID).Scan(&g.ID, &g.Name, &g.OwnerID, &ownerRow)
	if err != nil {
		return nil, err
	}
	members, _, err := db.groupMembers(ctx, groupID)
	if err != nil {
		return nil, err
	}
	g.Members = members
	return &g, nil
}

// notifyGroup pushes a frame to every member (optionally skipping one row id).
func (s *Server) notifyGroup(ctx context.Context, groupID string, except int64, frame wsFrame) {
	_, ids, err := s.DB.groupMembers(ctx, groupID)
	if err != nil {
		return
	}
	for _, id := range ids {
		if id == except {
			continue
		}
		s.Hub.Deliver(id, frame)
	}
}

// ---------- handlers ----------

type createGroupReq struct {
	Name string `json:"name"`
}

func (s *Server) handleCreateGroup(w http.ResponseWriter, r *http.Request) {
	var req createGroupReq
	if err := decode(r, &req); err != nil || len(req.Name) == 0 || len(req.Name) > 60 {
		writeError(w, http.StatusBadRequest, "bad name")
		return
	}
	id := RandomHex(10)
	now := time.Now().UTC().Format(time.RFC3339)
	me := accountID(r)
	if _, err := s.DB.ExecContext(r.Context(),
		`INSERT INTO groups (id, name, owner_id, created_at) VALUES (?, ?, ?, ?)`,
		id, req.Name, me, now); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	if _, err := s.DB.ExecContext(r.Context(),
		`INSERT INTO group_members (group_id, account_id, role, joined_at) VALUES (?, ?, 'owner', ?)`,
		id, me, now); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	info, err := s.DB.groupInfo(r.Context(), id)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	writeJSON(w, http.StatusOK, info)
}

func (s *Server) handleListGroups(w http.ResponseWriter, r *http.Request) {
	rows, err := s.DB.QueryContext(r.Context(),
		`SELECT g.id FROM groups g JOIN group_members m ON m.group_id = g.id
		 WHERE m.account_id = ? ORDER BY g.created_at DESC`, accountID(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			writeError(w, http.StatusInternalServerError, "db")
			return
		}
		ids = append(ids, id)
	}
	out := make([]*groupInfo, 0, len(ids))
	for _, id := range ids {
		if info, err := s.DB.groupInfo(r.Context(), id); err == nil {
			out = append(out, info)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"groups": out})
}

func (s *Server) handleGroupDetail(w http.ResponseWriter, r *http.Request) {
	groupID := r.PathValue("id")
	if _, ok := s.DB.roleInGroup(r.Context(), groupID, accountID(r)); !ok {
		writeError(w, http.StatusForbidden, "not a member")
		return
	}
	info, err := s.DB.groupInfo(r.Context(), groupID)
	if err != nil {
		writeError(w, http.StatusNotFound, "no such group")
		return
	}
	writeJSON(w, http.StatusOK, info)
}

type inviteReq struct {
	Username string `json:"username"`
}

func (s *Server) handleGroupInvite(w http.ResponseWriter, r *http.Request) {
	groupID := r.PathValue("id")
	role, ok := s.DB.roleInGroup(r.Context(), groupID, accountID(r))
	if !ok || (role != "owner" && role != "admin") {
		writeError(w, http.StatusForbidden, "admins only")
		return
	}
	var req inviteReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	invitee, err := s.DB.AccountByUsername(r.Context(), req.Username)
	if err != nil {
		writeError(w, http.StatusNotFound, "no such user")
		return
	}
	if _, member := s.DB.roleInGroup(r.Context(), groupID, invitee.ID); member {
		writeError(w, http.StatusConflict, "already a member")
		return
	}
	if _, err := s.DB.ExecContext(r.Context(),
		`INSERT OR IGNORE INTO group_invites (group_id, invitee_id, inviter_id, created_at)
		 VALUES (?, ?, ?, ?)`,
		groupID, invitee.ID, accountID(r), time.Now().UTC().Format(time.RFC3339)); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	if info, err := s.DB.groupInfo(r.Context(), groupID); err == nil {
		s.Hub.Deliver(invitee.ID, wsFrame{Kind: "groupInvite", Payload: info})
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleListGroupInvites(w http.ResponseWriter, r *http.Request) {
	rows, err := s.DB.QueryContext(r.Context(),
		`SELECT group_id FROM group_invites WHERE invitee_id = ?
		 ORDER BY created_at DESC`, accountID(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			writeError(w, http.StatusInternalServerError, "db")
			return
		}
		ids = append(ids, id)
	}
	out := make([]*groupInfo, 0, len(ids))
	for _, id := range ids {
		if info, err := s.DB.groupInfo(r.Context(), id); err == nil {
			out = append(out, info)
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"invites": out})
}

func (s *Server) handleAcceptGroupInvite(w http.ResponseWriter, r *http.Request) {
	groupID := r.PathValue("id")
	me := accountID(r)
	var one int
	err := s.DB.QueryRowContext(r.Context(),
		`SELECT 1 FROM group_invites WHERE group_id = ? AND invitee_id = ?`,
		groupID, me).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "no invite")
		return
	}
	if _, err := s.DB.ExecContext(r.Context(),
		`INSERT OR IGNORE INTO group_members (group_id, account_id, role, joined_at)
		 VALUES (?, ?, 'member', ?)`,
		groupID, me, time.Now().UTC().Format(time.RFC3339)); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	_, _ = s.DB.ExecContext(r.Context(),
		`DELETE FROM group_invites WHERE group_id = ? AND invitee_id = ?`, groupID, me)
	if info, err := s.DB.groupInfo(r.Context(), groupID); err == nil {
		s.notifyGroup(r.Context(), groupID, me, wsFrame{Kind: "groupUpdate", Payload: info})
		writeJSON(w, http.StatusOK, info)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleDeclineGroupInvite(w http.ResponseWriter, r *http.Request) {
	groupID := r.PathValue("id")
	_, _ = s.DB.ExecContext(r.Context(),
		`DELETE FROM group_invites WHERE group_id = ? AND invitee_id = ?`,
		groupID, accountID(r))
	w.WriteHeader(http.StatusNoContent)
}

type groupTargetReq struct {
	UserID string `json:"user_id"`
}

func (s *Server) resolveGroupTarget(w http.ResponseWriter, r *http.Request) (string, int64, bool) {
	groupID := r.PathValue("id")
	var req groupTargetReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return "", 0, false
	}
	numeric, err := strconv.ParseUint(req.UserID, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad user_id")
		return "", 0, false
	}
	var rowID int64
	err = s.DB.QueryRowContext(r.Context(),
		`SELECT id FROM accounts WHERE numeric_id = ?`, numeric).Scan(&rowID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "no such user")
		return "", 0, false
	}
	return groupID, rowID, err == nil
}

func (s *Server) handleGroupKick(w http.ResponseWriter, r *http.Request) {
	groupID, targetID, ok := s.resolveGroupTarget(w, r)
	if !ok {
		return
	}
	myRole, member := s.DB.roleInGroup(r.Context(), groupID, accountID(r))
	if !member || (myRole != "owner" && myRole != "admin") {
		writeError(w, http.StatusForbidden, "admins only")
		return
	}
	targetRole, _ := s.DB.roleInGroup(r.Context(), groupID, targetID)
	// The owner can never be kicked; admins can't kick other admins.
	if targetRole == "owner" || (myRole == "admin" && targetRole == "admin") {
		writeError(w, http.StatusForbidden, "cannot kick")
		return
	}
	if _, err := s.DB.ExecContext(r.Context(),
		`DELETE FROM group_members WHERE group_id = ? AND account_id = ?`,
		groupID, targetID); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	s.Hub.Deliver(targetID, wsFrame{Kind: "groupRemoved", Payload: map[string]string{"group_id": groupID}})
	if info, err := s.DB.groupInfo(r.Context(), groupID); err == nil {
		s.notifyGroup(r.Context(), groupID, 0, wsFrame{Kind: "groupUpdate", Payload: info})
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleGroupPromote(w http.ResponseWriter, r *http.Request) {
	groupID, targetID, ok := s.resolveGroupTarget(w, r)
	if !ok {
		return
	}
	// Only the owner promotes members to admin.
	if myRole, member := s.DB.roleInGroup(r.Context(), groupID, accountID(r)); !member || myRole != "owner" {
		writeError(w, http.StatusForbidden, "owner only")
		return
	}
	if _, err := s.DB.ExecContext(r.Context(),
		`UPDATE group_members SET role = 'admin'
		 WHERE group_id = ? AND account_id = ? AND role = 'member'`,
		groupID, targetID); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	if info, err := s.DB.groupInfo(r.Context(), groupID); err == nil {
		s.notifyGroup(r.Context(), groupID, 0, wsFrame{Kind: "groupUpdate", Payload: info})
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleGroupLeave(w http.ResponseWriter, r *http.Request) {
	groupID := r.PathValue("id")
	me := accountID(r)
	role, member := s.DB.roleInGroup(r.Context(), groupID, me)
	if !member {
		w.WriteHeader(http.StatusNoContent)
		return
	}
	if role == "owner" {
		// Owner leaving disbands the group.
		s.notifyGroup(r.Context(), groupID, 0,
			wsFrame{Kind: "groupRemoved", Payload: map[string]string{"group_id": groupID}})
		_, _ = s.DB.ExecContext(r.Context(), `DELETE FROM groups WHERE id = ?`, groupID)
		w.WriteHeader(http.StatusNoContent)
		return
	}
	_, _ = s.DB.ExecContext(r.Context(),
		`DELETE FROM group_members WHERE group_id = ? AND account_id = ?`, groupID, me)
	if info, err := s.DB.groupInfo(r.Context(), groupID); err == nil {
		s.notifyGroup(r.Context(), groupID, 0, wsFrame{Kind: "groupUpdate", Payload: info})
	}
	w.WriteHeader(http.StatusNoContent)
}

type groupMsgReq struct {
	Type    string `json:"type"`
	Payload string `json:"payload"`
}

// handleGroupMessage fans a message out to every other member as an envelope,
// reusing the 1:1 delivery + offline sync path (conversation_id = group id).
func (s *Server) handleGroupMessage(w http.ResponseWriter, r *http.Request) {
	groupID := r.PathValue("id")
	me, member := s.DB.roleInGroup(r.Context(), groupID, accountID(r))
	_ = me
	if !member {
		writeError(w, http.StatusForbidden, "not a member")
		return
	}
	var req groupMsgReq
	if err := decode(r, &req); err != nil || req.Type == "" {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	sender, err := s.DB.AccountByID(r.Context(), accountID(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	senderName := ""
	if sender.Username.Valid {
		senderName = sender.Username.String
	}
	_, ids, err := s.DB.groupMembers(r.Context(), groupID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	now := time.Now().UTC().Truncate(time.Second)
	for _, id := range ids {
		if id == sender.ID {
			continue
		}
		env := &Envelope{
			ID:             RandomHex(12),
			ConversationID: groupID,
			SenderID:       sender.ID,
			SenderNumeric:  sender.NumericID,
			SenderUsername: senderName,
			Type:           req.Type,
			Payload:        req.Payload,
			SentAt:         now,
		}
		if err := s.DB.StoreEnvelope(r.Context(), env, id); err == nil {
			s.Hub.Deliver(id, wsFrame{Kind: "message", Payload: env})
		}
	}
	w.WriteHeader(http.StatusNoContent)
}
