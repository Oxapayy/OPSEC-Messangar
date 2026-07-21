package main

import (
	"context"
	"database/sql"
	"errors"
	"time"

	_ "modernc.org/sqlite"
)

type DB struct{ *sql.DB }

func OpenDB(path string) (*DB, error) {
	sqlDB, err := sql.Open("sqlite", path+"?_pragma=journal_mode(WAL)&_pragma=foreign_keys(on)&_pragma=busy_timeout(5000)")
	if err != nil {
		return nil, err
	}
	sqlDB.SetMaxOpenConns(1) // SQLite prefers a single writer.
	if err := sqlDB.Ping(); err != nil {
		return nil, err
	}
	db := &DB{sqlDB}
	if err := db.migrate(); err != nil {
		return nil, err
	}
	return db, nil
}

func (db *DB) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS accounts (
			id            INTEGER PRIMARY KEY AUTOINCREMENT,
			numeric_id    INTEGER UNIQUE NOT NULL,
			auth_key_hash TEXT NOT NULL,
			username      TEXT UNIQUE COLLATE NOCASE,
			public_key    TEXT,
			created_at    TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS sessions (
			token       TEXT PRIMARY KEY,
			account_id  INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			created_at  TEXT NOT NULL,
			last_seen   TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS contacts (
			owner_id   INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			contact_id INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			added_at   TEXT NOT NULL,
			PRIMARY KEY (owner_id, contact_id)
		)`,
		`CREATE TABLE IF NOT EXISTS envelopes (
			id              TEXT PRIMARY KEY,
			conversation_id TEXT NOT NULL,
			sender_id       INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			recipient_id    INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			type            TEXT NOT NULL,
			payload         TEXT NOT NULL,
			sent_at         TEXT NOT NULL,
			delivered_at    TEXT
		)`,
		`CREATE INDEX IF NOT EXISTS idx_env_recipient_undelivered
			ON envelopes(recipient_id) WHERE delivered_at IS NULL`,
		`CREATE TABLE IF NOT EXISTS attachments (
			id         TEXT PRIMARY KEY,
			owner_id   INTEGER NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			size       INTEGER NOT NULL,
			uploaded   INTEGER NOT NULL DEFAULT 0,
			created_at TEXT NOT NULL
		)`,
		`CREATE TABLE IF NOT EXISTS apns_tokens (
			account_id INTEGER PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
			token      TEXT NOT NULL,
			updated_at TEXT NOT NULL
		)`,
	}
	for _, s := range stmts {
		if _, err := db.Exec(s); err != nil {
			return err
		}
	}
	return nil
}

// ---------- accounts ----------

type Account struct {
	ID          int64
	NumericID   uint64
	AuthKeyHash string
	Username    sql.NullString
	PublicKey   sql.NullString
	CreatedAt   time.Time
}

var ErrNotFound = errors.New("not found")

func (db *DB) InsertAccount(ctx context.Context, numericID uint64, hash string) (int64, error) {
	res, err := db.ExecContext(ctx, `INSERT INTO accounts (numeric_id, auth_key_hash, created_at) VALUES (?, ?, ?)`,
		numericID, hash, time.Now().UTC().Format(time.RFC3339))
	if err != nil {
		return 0, err
	}
	return res.LastInsertId()
}

func (db *DB) AccountByHash(ctx context.Context, hash string) (*Account, error) {
	// Note: Argon2id hashes are salted so we cannot lookup by hash directly.
	// Login flow: caller iterates or (better) uses a lookup shortcut. For a
	// self-hosted messenger with small userbase we scan; for scale, index by
	// a fast keyed HMAC of auth_key that's stored separately.
	rows, err := db.QueryContext(ctx,
		`SELECT id, numeric_id, auth_key_hash, username, public_key, created_at FROM accounts`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	for rows.Next() {
		var a Account
		var created string
		if err := rows.Scan(&a.ID, &a.NumericID, &a.AuthKeyHash, &a.Username, &a.PublicKey, &created); err != nil {
			return nil, err
		}
		if VerifyArgon2id(hash, a.AuthKeyHash) {
			a.CreatedAt, _ = time.Parse(time.RFC3339, created)
			return &a, nil
		}
	}
	return nil, ErrNotFound
}

func (db *DB) AccountByID(ctx context.Context, id int64) (*Account, error) {
	var a Account
	var created string
	err := db.QueryRowContext(ctx,
		`SELECT id, numeric_id, auth_key_hash, username, public_key, created_at
		 FROM accounts WHERE id = ?`, id).
		Scan(&a.ID, &a.NumericID, &a.AuthKeyHash, &a.Username, &a.PublicKey, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	a.CreatedAt, _ = time.Parse(time.RFC3339, created)
	return &a, nil
}

func (db *DB) AccountByUsername(ctx context.Context, username string) (*Account, error) {
	var a Account
	var created string
	err := db.QueryRowContext(ctx,
		`SELECT id, numeric_id, auth_key_hash, username, public_key, created_at
		 FROM accounts WHERE username = ? COLLATE NOCASE`, username).
		Scan(&a.ID, &a.NumericID, &a.AuthKeyHash, &a.Username, &a.PublicKey, &created)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, ErrNotFound
	}
	if err != nil {
		return nil, err
	}
	a.CreatedAt, _ = time.Parse(time.RFC3339, created)
	return &a, nil
}

func (db *DB) NumericIDExists(ctx context.Context, id uint64) (bool, error) {
	var one int
	err := db.QueryRowContext(ctx, `SELECT 1 FROM accounts WHERE numeric_id = ?`, id).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	return err == nil, err
}

func (db *DB) SetUsername(ctx context.Context, accountID int64, username string) error {
	_, err := db.ExecContext(ctx,
		`UPDATE accounts SET username = ? WHERE id = ?`, username, accountID)
	return err
}

func (db *DB) UsernameAvailable(ctx context.Context, username string) (bool, error) {
	var one int
	err := db.QueryRowContext(ctx,
		`SELECT 1 FROM accounts WHERE username = ? COLLATE NOCASE`, username).Scan(&one)
	if errors.Is(err, sql.ErrNoRows) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return false, nil
}

// ---------- sessions ----------

func (db *DB) CreateSession(ctx context.Context, accountID int64) (string, error) {
	token := RandomHex(32)
	now := time.Now().UTC().Format(time.RFC3339)
	_, err := db.ExecContext(ctx,
		`INSERT INTO sessions (token, account_id, created_at, last_seen) VALUES (?, ?, ?, ?)`,
		token, accountID, now, now)
	return token, err
}

func (db *DB) AccountIDForToken(ctx context.Context, token string) (int64, error) {
	var id int64
	err := db.QueryRowContext(ctx,
		`SELECT account_id FROM sessions WHERE token = ?`, token).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return 0, ErrNotFound
	}
	if err != nil {
		return 0, err
	}
	_, _ = db.ExecContext(ctx, `UPDATE sessions SET last_seen = ? WHERE token = ?`,
		time.Now().UTC().Format(time.RFC3339), token)
	return id, nil
}

// ---------- contacts ----------

func (db *DB) AddContact(ctx context.Context, owner, contact int64) error {
	_, err := db.ExecContext(ctx,
		`INSERT OR IGNORE INTO contacts (owner_id, contact_id, added_at) VALUES (?, ?, ?)`,
		owner, contact, time.Now().UTC().Format(time.RFC3339))
	return err
}

func (db *DB) ListContacts(ctx context.Context, owner int64) ([]*Account, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT a.id, a.numeric_id, a.auth_key_hash, a.username, a.public_key, a.created_at
		 FROM accounts a JOIN contacts c ON c.contact_id = a.id
		 WHERE c.owner_id = ? ORDER BY c.added_at DESC`, owner)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Account
	for rows.Next() {
		var a Account
		var created string
		if err := rows.Scan(&a.ID, &a.NumericID, &a.AuthKeyHash, &a.Username, &a.PublicKey, &created); err != nil {
			return nil, err
		}
		a.CreatedAt, _ = time.Parse(time.RFC3339, created)
		out = append(out, &a)
	}
	return out, nil
}

// ---------- envelopes ----------

type Envelope struct {
	ID             string    `json:"id"`
	ConversationID string    `json:"conversation_id"`
	SenderID       int64     `json:"-"`
	SenderNumeric  uint64    `json:"sender_id,string"`
	Type           string    `json:"type"`
	Payload        string    `json:"payload"`
	SentAt         time.Time `json:"sent_at"`
}

func (db *DB) StoreEnvelope(ctx context.Context, e *Envelope, recipientID int64) error {
	_, err := db.ExecContext(ctx,
		`INSERT INTO envelopes
		 (id, conversation_id, sender_id, recipient_id, type, payload, sent_at)
		 VALUES (?, ?, ?, ?, ?, ?, ?)`,
		e.ID, e.ConversationID, e.SenderID, recipientID, e.Type, e.Payload,
		e.SentAt.UTC().Format(time.RFC3339Nano))
	return err
}

func (db *DB) UndeliveredFor(ctx context.Context, recipientID int64) ([]*Envelope, error) {
	rows, err := db.QueryContext(ctx,
		`SELECT e.id, e.conversation_id, e.sender_id, a.numeric_id, e.type, e.payload, e.sent_at
		 FROM envelopes e JOIN accounts a ON a.id = e.sender_id
		 WHERE e.recipient_id = ? AND e.delivered_at IS NULL
		 ORDER BY e.sent_at ASC LIMIT 500`, recipientID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []*Envelope
	for rows.Next() {
		var e Envelope
		var sent string
		if err := rows.Scan(&e.ID, &e.ConversationID, &e.SenderID, &e.SenderNumeric,
			&e.Type, &e.Payload, &sent); err != nil {
			return nil, err
		}
		e.SentAt, _ = time.Parse(time.RFC3339Nano, sent)
		out = append(out, &e)
	}
	return out, nil
}

func (db *DB) MarkDelivered(ctx context.Context, envelopeID string) error {
	_, err := db.ExecContext(ctx,
		`UPDATE envelopes SET delivered_at = ? WHERE id = ?`,
		time.Now().UTC().Format(time.RFC3339Nano), envelopeID)
	return err
}

// ---------- attachments ----------

func (db *DB) CreateAttachment(ctx context.Context, ownerID int64, size int64) (string, error) {
	id := RandomHex(16)
	_, err := db.ExecContext(ctx,
		`INSERT INTO attachments (id, owner_id, size, created_at) VALUES (?, ?, ?, ?)`,
		id, ownerID, size, time.Now().UTC().Format(time.RFC3339))
	return id, err
}

func (db *DB) MarkAttachmentUploaded(ctx context.Context, id string, ownerID int64) error {
	_, err := db.ExecContext(ctx,
		`UPDATE attachments SET uploaded = 1 WHERE id = ? AND owner_id = ?`, id, ownerID)
	return err
}

// ---------- apns ----------

func (db *DB) UpsertAPNsToken(ctx context.Context, accountID int64, token string) error {
	_, err := db.ExecContext(ctx,
		`INSERT INTO apns_tokens (account_id, token, updated_at) VALUES (?, ?, ?)
		 ON CONFLICT(account_id) DO UPDATE SET token = excluded.token, updated_at = excluded.updated_at`,
		accountID, token, time.Now().UTC().Format(time.RFC3339))
	return err
}
