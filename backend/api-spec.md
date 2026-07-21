# API spec — client ↔ backend contract

All requests are JSON. All authenticated requests carry
`Authorization: Bearer <sessionToken>`. Fields use snake_case on the wire;
the client decodes with `keyDecodingStrategy = .convertFromSnakeCase`.

## Auth

### `POST /v1/register`
Public. Creates a new account.
```json
{ "auth_key": "<hex(sha256(recovery_code)) – TODO: swap to argon2id>",
  "numeric_id": 123456789012345678 }
```
Response:
```json
{ "session_token": "..." }
```
Errors: 409 if `numeric_id` collides (client MUST regenerate and retry).

### `POST /v1/login`
Public.
```json
{ "auth_key": "..." }
```
Response:
```json
{ "session_token": "...",
  "profile": { "id": "...", "username": "...",
               "numeric_id": 12345, "public_key": null } }
```

### `PUT /v1/username`  (auth)
```json
{ "username": "alice" }
```
409 if taken.

### `GET /v1/username/available?u=alice`
Public.
```json
{ "available": true }
```

## Contacts

### `GET /v1/users/lookup?username=alice`  (auth)
Response: `UserProfile`.

### `POST /v1/contacts`  (auth)
```json
{ "user_id": "..." }
```

### `GET /v1/contacts`  (auth)
```json
{ "contacts": [UserProfile, ...] }
```

## Messages

### `POST /v1/messages`  (auth)
```json
{ "conversation_id": "...",
  "type": "text|image|callInvite|systemNotice",
  "payload": "<base64 opaque ciphertext>" }
```

### `POST /v1/attachments`  (auth)
```json
{ "size": 12345 }
```
Response:
```json
{ "upload_url": "https://...", "file_id": "..." }
```
Client then `PUT`s the raw bytes to `upload_url`.

## Calls

### `POST /v1/calls`  (auth)
```json
{ "peer_id": "...", "sdp": "<offer>" }
```
Response:
```json
{ "call_id": "...", "sdp_answer": null }
```
Real signalling happens over the WebSocket (`callOffer`/`callAnswer`/
`callEnd` events).

## Privacy signals

### `POST /v1/privacy/screenshot`  (auth)
Client tells the backend that the current user just took a screenshot in a
conversation. The server delivers a `systemNotice` message to the peer so
they see "@alice took a screenshot".
```json
{ "conversation_id": "...", "media_id": "..." }
```
Response: 204 No Content.

## Push

### `POST /v1/push/apns`  (auth)
```json
{ "token": "<hex apns token>" }
```

## WebSocket — `GET /ws`  (auth via `Authorization` header)

Server → client messages:
```json
{ "kind": "message",   "payload": MessageEnvelope }
{ "kind": "typing",    "payload": { "conversation_id": "...", "user_id": "..." } }
{ "kind": "callOffer", "payload": { "from": "...", "sdp": "...", "call_id": "..." } }
{ "kind": "callAnswer","payload": { "call_id": "...", "sdp": "..." } }
{ "kind": "callEnd",   "payload": { "call_id": "..." } }
{ "kind": "presence",  "payload": { "user_id": "...", "online": "true" } }
```

`MessageEnvelope`:
```json
{ "id": "...", "conversation_id": "...", "sender_id": "...",
  "type": "text|image|...", "payload": "<base64>", "sent_at": "ISO8601" }
```
