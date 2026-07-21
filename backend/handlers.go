package main

import (
	"database/sql"
	"errors"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"time"
)

// ---------- auth ----------

type registerReq struct {
	AuthKey   string `json:"auth_key"`
	NumericID uint64 `json:"numeric_id"`
}
type registerResp struct {
	SessionToken string `json:"session_token"`
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	var req registerReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	if err := AuthKeyLooksValid(req.AuthKey); err != nil {
		writeError(w, http.StatusBadRequest, "bad auth_key")
		return
	}
	if req.NumericID == 0 {
		writeError(w, http.StatusBadRequest, "bad numeric_id")
		return
	}
	exists, _ := s.DB.NumericIDExists(r.Context(), req.NumericID)
	if exists {
		writeError(w, http.StatusConflict, "numeric_id collision, regenerate")
		return
	}
	hash := HashArgon2id(req.AuthKey)
	accountID, err := s.DB.InsertAccount(r.Context(), req.NumericID, hash)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "insert failed")
		return
	}
	token, err := s.DB.CreateSession(r.Context(), accountID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "session failed")
		return
	}
	writeJSON(w, http.StatusOK, registerResp{SessionToken: token})
}

type loginReq struct {
	AuthKey string `json:"auth_key"`
}
type profile struct {
	ID        string  `json:"id"`
	Username  string  `json:"username"`
	NumericID uint64  `json:"numeric_id"`
	PublicKey *string `json:"public_key"`
}
type loginResp struct {
	SessionToken string  `json:"session_token"`
	Profile      profile `json:"profile"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginReq
	if err := decode(r, &req); err != nil || AuthKeyLooksValid(req.AuthKey) != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	acct, err := s.DB.AccountByHash(r.Context(), req.AuthKey)
	if err != nil {
		time.Sleep(300 * time.Millisecond) // uniform-ish delay
		writeError(w, http.StatusUnauthorized, "no matching account")
		return
	}
	token, err := s.DB.CreateSession(r.Context(), acct.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "session failed")
		return
	}
	writeJSON(w, http.StatusOK, loginResp{
		SessionToken: token,
		Profile:      acctToProfile(acct),
	})
}

var usernameRE = regexp.MustCompile(`^[a-z0-9_]{3,20}$`)

func (s *Server) handleUsernameAvailable(w http.ResponseWriter, r *http.Request) {
	u := r.URL.Query().Get("u")
	if !usernameRE.MatchString(u) {
		writeJSON(w, http.StatusOK, map[string]bool{"available": false})
		return
	}
	ok, err := s.DB.UsernameAvailable(r.Context(), u)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	writeJSON(w, http.StatusOK, map[string]bool{"available": ok})
}

type claimUsernameReq struct {
	Username string `json:"username"`
}

func (s *Server) handleClaimUsername(w http.ResponseWriter, r *http.Request) {
	var req claimUsernameReq
	if err := decode(r, &req); err != nil || !usernameRE.MatchString(req.Username) {
		writeError(w, http.StatusBadRequest, "bad username")
		return
	}
	ok, _ := s.DB.UsernameAvailable(r.Context(), req.Username)
	if !ok {
		writeError(w, http.StatusConflict, "taken")
		return
	}
	if err := s.DB.SetUsername(r.Context(), accountID(r), req.Username); err != nil {
		writeError(w, http.StatusInternalServerError, "update")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---------- contacts ----------

func (s *Server) handleLookupUser(w http.ResponseWriter, r *http.Request) {
	u := r.URL.Query().Get("username")
	acct, err := s.DB.AccountByUsername(r.Context(), u)
	if err != nil {
		writeError(w, http.StatusNotFound, "no such user")
		return
	}
	writeJSON(w, http.StatusOK, acctToProfile(acct))
}

type addContactReq struct {
	UserID string `json:"user_id"`
}

func (s *Server) handleAddContact(w http.ResponseWriter, r *http.Request) {
	var req addContactReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	id, err := strconv.ParseInt(req.UserID, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad user_id")
		return
	}
	if _, err := s.DB.AccountByID(r.Context(), id); err != nil {
		writeError(w, http.StatusNotFound, "no such user")
		return
	}
	if err := s.DB.AddContact(r.Context(), accountID(r), id); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleListContacts(w http.ResponseWriter, r *http.Request) {
	contacts, err := s.DB.ListContacts(r.Context(), accountID(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	out := make([]profile, 0, len(contacts))
	for _, c := range contacts {
		out = append(out, acctToProfile(c))
	}
	writeJSON(w, http.StatusOK, map[string]any{"contacts": out})
}

// ---------- messages ----------

type sendMsgReq struct {
	ConversationID string `json:"conversation_id"`
	RecipientID    string `json:"recipient_id"`
	Type           string `json:"type"`
	Payload        string `json:"payload"`
}

func (s *Server) handleSendMessage(w http.ResponseWriter, r *http.Request) {
	var req sendMsgReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	if req.ConversationID == "" || req.RecipientID == "" || req.Type == "" {
		writeError(w, http.StatusBadRequest, "missing fields")
		return
	}
	recipientNumeric, err := strconv.ParseUint(req.RecipientID, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad recipient_id")
		return
	}
	// Look up recipient by numeric ID.
	var recipID int64
	err = s.DB.QueryRowContext(r.Context(),
		`SELECT id FROM accounts WHERE numeric_id = ?`, recipientNumeric).Scan(&recipID)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, "no such recipient")
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	me, err := s.DB.AccountByID(r.Context(), accountID(r))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	env := &Envelope{
		ID:             RandomHex(12),
		ConversationID: req.ConversationID,
		SenderID:       me.ID,
		SenderNumeric:  me.NumericID,
		Type:           req.Type,
		Payload:        req.Payload,
		SentAt:         time.Now().UTC(),
	}
	if err := s.DB.StoreEnvelope(r.Context(), env, recipID); err != nil {
		writeError(w, http.StatusInternalServerError, "store")
		return
	}
	// Push to online recipient (best effort). Marking delivered happens when
	// the recipient acks over the WS.
	s.Hub.Deliver(recipID, wsFrame{Kind: "message", Payload: env})
	w.WriteHeader(http.StatusNoContent)
}

// ---------- attachments ----------

type attachReq struct {
	Size int64 `json:"size"`
}
type attachResp struct {
	UploadURL string `json:"upload_url"`
	FileID    string `json:"file_id"`
}

func (s *Server) handleRequestAttachment(w http.ResponseWriter, r *http.Request) {
	var req attachReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	if req.Size <= 0 || req.Size > s.Cfg.MaxUploadSize {
		writeError(w, http.StatusBadRequest, "size out of range")
		return
	}
	id, err := s.DB.CreateAttachment(r.Context(), accountID(r), req.Size)
	if err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	writeJSON(w, http.StatusOK, attachResp{
		UploadURL: "/v1/attachments/" + id,
		FileID:    id,
	})
}

func (s *Server) handleUploadAttachment(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if id == "" {
		writeError(w, http.StatusBadRequest, "bad id")
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, s.Cfg.MaxUploadSize)
	if err := os.MkdirAll(s.Cfg.UploadDir, 0o750); err != nil {
		writeError(w, http.StatusInternalServerError, "mkdir")
		return
	}
	f, err := os.Create(filepath.Join(s.Cfg.UploadDir, id))
	if err != nil {
		writeError(w, http.StatusInternalServerError, "create")
		return
	}
	defer f.Close()
	if _, err := io.Copy(f, r.Body); err != nil {
		writeError(w, http.StatusBadRequest, "upload")
		return
	}
	if err := s.DB.MarkAttachmentUploaded(r.Context(), id, accountID(r)); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleDownloadAttachment(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	path := filepath.Join(s.Cfg.UploadDir, id)
	f, err := os.Open(path)
	if err != nil {
		writeError(w, http.StatusNotFound, "not found")
		return
	}
	defer f.Close()
	w.Header().Set("Content-Type", "application/octet-stream")
	_, _ = io.Copy(w, f)
}

// ---------- calls ----------

type callReq struct {
	PeerID string `json:"peer_id"`
	SDP    string `json:"sdp"`
}
type callResp struct {
	CallID    string  `json:"call_id"`
	SDPAnswer *string `json:"sdp_answer"`
}

func (s *Server) handleStartCall(w http.ResponseWriter, r *http.Request) {
	var req callReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	peerNumeric, err := strconv.ParseUint(req.PeerID, 10, 64)
	if err != nil {
		writeError(w, http.StatusBadRequest, "bad peer_id")
		return
	}
	var peerID int64
	err = s.DB.QueryRowContext(r.Context(),
		`SELECT id FROM accounts WHERE numeric_id = ?`, peerNumeric).Scan(&peerID)
	if err != nil {
		writeError(w, http.StatusNotFound, "no peer")
		return
	}
	callID := RandomHex(12)
	me, _ := s.DB.AccountByID(r.Context(), accountID(r))
	s.Hub.Deliver(peerID, wsFrame{
		Kind: "callOffer",
		Payload: map[string]any{
			"from":    strconv.FormatUint(me.NumericID, 10),
			"sdp":     req.SDP,
			"call_id": callID,
		},
	})
	writeJSON(w, http.StatusOK, callResp{CallID: callID, SDPAnswer: nil})
}

// ---------- privacy signals ----------

type screenshotReq struct {
	ConversationID string `json:"conversation_id"`
	MediaID        string `json:"media_id"`
}

func (s *Server) handleScreenshot(w http.ResponseWriter, r *http.Request) {
	var req screenshotReq
	if err := decode(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	me, _ := s.DB.AccountByID(r.Context(), accountID(r))
	// System-notice envelope, broadcast to everyone in the conversation
	// besides the sender. Since we don't model membership explicitly, this
	// looks up the other party via undelivered/history — for MVP we just log.
	s.Hub.Broadcast(wsFrame{
		Kind: "systemNotice",
		Payload: map[string]any{
			"conversation_id": req.ConversationID,
			"actor":           strconv.FormatUint(me.NumericID, 10),
			"kind":            "screenshot",
			"media_id":        req.MediaID,
		},
	}, me.ID)
	w.WriteHeader(http.StatusNoContent)
}

// ---------- push ----------

type apnsReq struct {
	Token string `json:"token"`
}

func (s *Server) handleRegisterAPNs(w http.ResponseWriter, r *http.Request) {
	var req apnsReq
	if err := decode(r, &req); err != nil || req.Token == "" {
		writeError(w, http.StatusBadRequest, "bad body")
		return
	}
	if err := s.DB.UpsertAPNsToken(r.Context(), accountID(r), req.Token); err != nil {
		writeError(w, http.StatusInternalServerError, "db")
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// ---------- helpers ----------

func acctToProfile(a *Account) profile {
	uname := ""
	if a.Username.Valid {
		uname = a.Username.String
	}
	var pk *string
	if a.PublicKey.Valid {
		v := a.PublicKey.String
		pk = &v
	}
	return profile{
		ID:        strconv.FormatUint(a.NumericID, 10),
		Username:  uname,
		NumericID: a.NumericID,
		PublicKey: pk,
	}
}
