# OPSEC-Messangar backend

Small self-hostable HTTP + WebSocket backend for the iOS client. Written
in Go (single binary, no CGO), stores everything in SQLite, and is
designed to run behind a Tor hidden service on a Linux VPS.

## Build

```
cd backend
go mod tidy
make build
```

Produces a static binary `./opsec-backend`. Run locally:

```
make run
```

Default listen address is `127.0.0.1:8080` and data lives in
`./_data/` (override with `OPSEC_LISTEN`, `OPSEC_DATA_DIR`).

## Endpoints

The wire contract is documented in [`api-spec.md`](./api-spec.md). Every
endpoint returns JSON with `snake_case` field names.

## Deployment

Full copy-paste-ready deployment guide, from a fresh Ubuntu install to a
working Tor hidden service, is in [`VPS_SETUP.md`](./VPS_SETUP.md).

## Notes

- **Auth key hashing** — the client sends `sha256(recovery_code)` as
  `auth_key`; the server Argon2id-hashes that value before storage
  (`auth.go`). Login therefore needs to iterate over accounts and verify —
  fine at self-hosted scale (a few thousand users). For millions of users,
  add a keyed HMAC index column and look up by that first.
- **No plaintext in envelopes** — the server relays base64 opaque
  ciphertext blobs. It never sees message contents (once the client wires
  up real E2EE — currently the "ciphertext" is a placeholder key).
- **APNs** — the token is stored per account so the server can wake the
  client. Actually sending pushes requires configuring an APNs auth key
  and calling Apple's HTTP/2 API (not shipped here — mark
  `TODO(backend)`).
- **Attachments** — stored on local disk under `OPSEC_UPLOADS`. Upload
  URLs are relative paths (`/v1/attachments/<id>`); the client uploads
  with `PUT` and downloads with `GET`.
