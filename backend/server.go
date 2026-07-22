package main

import (
	"context"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strings"
	"time"
)

type Server struct {
	DB  *DB
	Hub *Hub
	Cfg Config
}

type ctxKey string

const ctxAccountID ctxKey = "account_id"

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()

	// Public
	mux.HandleFunc("POST /v1/register", s.handleRegister)
	mux.HandleFunc("POST /v1/login", s.handleLogin)
	mux.HandleFunc("GET /v1/username/available", s.handleUsernameAvailable)

	// Auth-required
	mux.Handle("PUT /v1/username", s.authed(s.handleClaimUsername))
	mux.Handle("GET /v1/users/lookup", s.authed(s.handleLookupUser))
	mux.Handle("POST /v1/contacts", s.authed(s.handleAddContact))
	mux.Handle("GET /v1/contacts", s.authed(s.handleListContacts))
	mux.Handle("GET /v1/contacts/requests", s.authed(s.handleListContactRequests))
	mux.Handle("DELETE /v1/contacts/{id}", s.authed(s.handleRemoveContact))
	mux.Handle("POST /v1/blocks", s.authed(s.handleBlock))
	mux.Handle("GET /v1/blocks", s.authed(s.handleListBlocked))
	mux.Handle("DELETE /v1/blocks/{id}", s.authed(s.handleUnblock))
	mux.Handle("POST /v1/messages", s.authed(s.handleSendMessage))
	mux.Handle("POST /v1/attachments", s.authed(s.handleRequestAttachment))
	mux.Handle("PUT /v1/attachments/{id}", s.authed(s.handleUploadAttachment))
	mux.Handle("GET /v1/attachments/{id}", s.authed(s.handleDownloadAttachment))
	mux.Handle("POST /v1/calls", s.authed(s.handleStartCall))
	mux.Handle("POST /v1/privacy/screenshot", s.authed(s.handleScreenshot))
	mux.Handle("POST /v1/push/apns", s.authed(s.handleRegisterAPNs))
	mux.Handle("GET /ws", s.authed(s.handleWS))

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte("ok"))
	})

	return withLogging(mux)
}

func (s *Server) authed(h http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		auth := r.Header.Get("Authorization")
		if !strings.HasPrefix(auth, "Bearer ") {
			writeError(w, http.StatusUnauthorized, "missing bearer token")
			return
		}
		token := strings.TrimPrefix(auth, "Bearer ")
		accountID, err := s.DB.AccountIDForToken(r.Context(), token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "invalid token")
			return
		}
		ctx := context.WithValue(r.Context(), ctxAccountID, accountID)
		h(w, r.WithContext(ctx))
	})
}

func accountID(r *http.Request) int64 {
	v, _ := r.Context().Value(ctxAccountID).(int64)
	return v
}

// ---------- helpers ----------

func writeJSON(w http.ResponseWriter, code int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(code)
	_ = json.NewEncoder(w).Encode(v)
}

func writeError(w http.ResponseWriter, code int, msg string) {
	writeJSON(w, code, map[string]string{"error": msg})
}

func decode(r *http.Request, v any) error {
	r.Body = http.MaxBytesReader(nil, r.Body, 1<<20) // 1 MiB request cap
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	return dec.Decode(v)
}

func withLogging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %s", r.Method, r.URL.Path, time.Since(start))
	})
}

// Common error shortcuts.
func isNotFound(err error) bool { return errors.Is(err, ErrNotFound) }
