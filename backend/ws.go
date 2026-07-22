package main

import (
	"context"
	"encoding/json"
	"log"
	"net/http"
	"sync"
	"time"

	"github.com/coder/websocket"
)

type wsFrame struct {
	Kind    string `json:"kind"`
	Payload any    `json:"payload"`
}

// Hub tracks live WS connections per account.
type Hub struct {
	mu    sync.RWMutex
	conns map[int64]map[*wsConn]struct{}
	in    chan hubMessage
}

type hubMessage struct {
	target int64 // 0 = broadcast
	except int64 // when broadcasting, skip this account
	frame  wsFrame
}

type wsConn struct {
	accountID int64
	conn      *websocket.Conn
	send      chan wsFrame
}

func NewHub() *Hub {
	return &Hub{
		conns: map[int64]map[*wsConn]struct{}{},
		in:    make(chan hubMessage, 256),
	}
}

func (h *Hub) Run() {
	for msg := range h.in {
		h.mu.RLock()
		if msg.target != 0 {
			for c := range h.conns[msg.target] {
				select {
				case c.send <- msg.frame:
				default:
				}
			}
		} else {
			for id, set := range h.conns {
				if id == msg.except {
					continue
				}
				for c := range set {
					select {
					case c.send <- msg.frame:
					default:
					}
				}
			}
		}
		h.mu.RUnlock()
	}
}

func (h *Hub) Deliver(accountID int64, f wsFrame) {
	h.in <- hubMessage{target: accountID, frame: f}
}

func (h *Hub) Broadcast(f wsFrame, except int64) {
	h.in <- hubMessage{except: except, frame: f}
}

func (h *Hub) register(c *wsConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.conns[c.accountID] == nil {
		h.conns[c.accountID] = map[*wsConn]struct{}{}
	}
	h.conns[c.accountID][c] = struct{}{}
}

func (h *Hub) unregister(c *wsConn) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if set := h.conns[c.accountID]; set != nil {
		delete(set, c)
		if len(set) == 0 {
			delete(h.conns, c.accountID)
		}
	}
}

// ---------- HTTP handler ----------

func (s *Server) handleWS(w http.ResponseWriter, r *http.Request) {
	c, err := websocket.Accept(w, r, &websocket.AcceptOptions{
		InsecureSkipVerify: true, // Tor hidden service; no browser Origin to check.
	})
	if err != nil {
		return
	}
	conn := &wsConn{
		accountID: accountID(r),
		conn:      c,
		send:      make(chan wsFrame, 32),
	}
	s.Hub.register(conn)
	defer s.Hub.unregister(conn)
	defer c.Close(websocket.StatusNormalClosure, "bye")

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	// Flush any undelivered envelopes on connect.
	if backlog, err := s.DB.UndeliveredFor(ctx, conn.accountID); err == nil {
		for _, env := range backlog {
			conn.send <- wsFrame{Kind: "message", Payload: env}
		}
	}

	go s.readPump(ctx, conn)
	s.writePump(ctx, conn)
}

func (s *Server) readPump(ctx context.Context, c *wsConn) {
	for {
		_, data, err := c.conn.Read(ctx)
		if err != nil {
			return
		}
		var f wsFrame
		if err := json.Unmarshal(data, &f); err != nil {
			continue
		}
		switch f.Kind {
		case "ack":
			// { "kind": "ack", "payload": { "id": "..." } }
			if m, ok := f.Payload.(map[string]any); ok {
				if id, _ := m["id"].(string); id != "" {
					_ = s.DB.MarkDelivered(ctx, id)
				}
			}
		case "callOffer", "callAccept", "callReject", "callAnswer",
			"callEnd", "callAudio", "typing",
			// Secret chat is entirely socket-relayed — never persisted.
			// If the peer's offline the frame is dropped, which is exactly
			// what "ephemeral" means.
			"secretInvite", "secretJoin", "secretDecline", "secretLeave",
			"secretMessage":
			// Relay signalling / audio to the other party. Blocked pairs
			// can't ring each other.
			if m, ok := f.Payload.(map[string]any); ok {
				if peerNumStr, _ := m["peer_id"].(string); peerNumStr != "" {
					var peerID int64
					_ = s.DB.QueryRowContext(ctx,
						`SELECT id FROM accounts WHERE numeric_id = ?`, peerNumStr).Scan(&peerID)
					if peerID != 0 {
						if blocked, _ := s.DB.IsBlocked(ctx, c.accountID, peerID); !blocked {
							s.Hub.Deliver(peerID, f)
						}
					}
				}
			}
		}
	}
}

func (s *Server) writePump(ctx context.Context, c *wsConn) {
	ping := time.NewTicker(30 * time.Second)
	defer ping.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case f, ok := <-c.send:
			if !ok {
				return
			}
			data, _ := json.Marshal(f)
			if err := c.conn.Write(ctx, websocket.MessageText, data); err != nil {
				return
			}
		case <-ping.C:
			if err := c.conn.Ping(ctx); err != nil {
				log.Printf("ws ping failed: %v", err)
				return
			}
		}
	}
}
