# API spec — client ↔ backend contract

All requests and responses are JSON with `snake_case` field names. All
authenticated requests carry `Authorization: Bearer <session_token>`.

## Auth

### `POST /v1/register`  (public)
Creates a new account. `numeric_id` must be a fresh, client-generated
64-bit-ish integer; the server 409s on collision and the client must
regenerate.

```json
{ "auth_key": "<hex(sha256(recovery_code))>",
  "numeric_id": 123456789012345678 }
```
→
```json
{ "session_token": "..." }
```

### `POST /v1/login`  (public)
```json
{ "auth_key": "..." }
```
→
```json
{ "session_token": "...",
  "profile": { "id": "...", "username": "...",
               "numeric_id": 12345, "public_key": null } }
```

### `GET /v1/username/available?u=alice`  (public)
```json
{ "available": true }
```

### `PUT /v1/username`  (auth)
```json
{ "username": "alice" }
```
409 if taken.

## Contacts

### `GET /v1/users/lookup?username=alice`  (auth)
Returns a `profile`.

### `POST /v1/contacts`  (auth)
```json
{ "user_id": "12345" }
```

### `GET /v1/contacts`  (auth)
```json
{ "contacts": [profile, ...] }
```

## Messages

### `POST /v1/messages`  (auth)
```json
{ "conversation_id": "...",
  "recipient_id":    "12345",
  "type":            "text|image|viewOnceImage|callInvite|systemNotice",
  "payload":         "<base64 opaque ciphertext>" }
```
Server stores the envelope and, if the recipient is online, pushes it
over the WebSocket immediately.

## Attachments

### `POST /v1/attachments`  (auth)
```json
{ "size": 12345 }
```
→
```json
{ "upload_url": "/v1/attachments/<id>", "file_id": "..." }
```

Client then `PUT`s the raw bytes to `upload_url` (auth required, same
bearer token). Downloading is `GET /v1/attachments/<id>`.

## Calls

### `POST /v1/calls`  (auth)
```json
{ "peer_id": "12345", "sdp": "<offer>" }
```
→
```json
{ "call_id": "...", "sdp_answer": null }
```
The server also pushes a `callOffer` WS frame to the peer.

## Privacy signals

### `POST /v1/privacy/screenshot`  (auth)
```json
{ "conversation_id": "...", "media_id": "..." }
```

## Push

### `POST /v1/push/apns`  (auth)
```json
{ "token": "<hex apns token>" }
```

## WebSocket — `GET /ws`  (auth)

Bearer token in the Authorization header. Frames are JSON:

```json
{ "kind": "message",       "payload": Envelope }
{ "kind": "systemNotice",  "payload": { ... } }
{ "kind": "callOffer",     "payload": { "from": "...", "sdp": "...", "call_id": "..." } }
{ "kind": "callAnswer",    "payload": { "call_id": "...", "sdp": "...", "peer_id": "..." } }
{ "kind": "callEnd",       "payload": { "call_id": "...", "peer_id": "..." } }
{ "kind": "typing",        "payload": { "conversation_id": "...", "peer_id": "..." } }
{ "kind": "presence",      "payload": { "user_id": "...", "online": "true" } }
```

Client → server:

```json
// Acknowledge a delivered envelope so the server can mark it delivered.
{ "kind": "ack", "payload": { "id": "<envelope id>" } }

// Signalling relay. peer_id is the recipient's numeric_id.
{ "kind": "callAnswer", "payload": { "peer_id": "...", "call_id": "...", "sdp": "..." } }
{ "kind": "callEnd",    "payload": { "peer_id": "...", "call_id": "..." } }
{ "kind": "typing",     "payload": { "peer_id": "...", "conversation_id": "..." } }
```

`Envelope`:
```json
{ "id": "...", "conversation_id": "...", "sender_id": "12345",
  "type": "text|image|...", "payload": "<base64>", "sent_at": "ISO8601" }
```
