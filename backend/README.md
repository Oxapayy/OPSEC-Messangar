# Backend (not yet implemented)

The VPS backend is not written yet. The iOS client talks to whatever host
is configured in
[`ios/OPSECMessenger/Config/BackendConfig.swift`](../ios/OPSECMessenger/Config/BackendConfig.swift).

The wire contract the client already expects is in
[`api-spec.md`](./api-spec.md). Implement any of it — Rust (axum, actix),
Go (net/http, chi), or Elixir/Phoenix all fit — and the client will connect
without further changes.

## Deployment sketch

1. Ubuntu 22.04 VPS.
2. Install `tor`, expose the service as a hidden v3 onion:

   ```
   HiddenServiceDir /var/lib/tor/opsec/
   HiddenServicePort 443 127.0.0.1:8080
   ```

3. Reverse-proxy through nginx or run the app directly on 8080.
4. Put the `.onion` hostname (`/var/lib/tor/opsec/hostname`) into
   `BackendConfig.onionHost`.
5. Optional clearnet fallback: only useful for dev; leave empty in production.

## Data model (sketch)

- `accounts(auth_key_hash, numeric_id, created_at)` — auth_key_hash is
  Argon2id(auth_key). numeric_id is the value picked by the client at
  registration and is unique.
- `usernames(username, account_id)` — separate table so usernames are
  claimable/releasable without rewriting accounts.
- `contacts(owner_id, contact_id, added_at)`.
- `envelopes(id, recipient_id, ciphertext, sent_at, delivered_at)` —
  opaque; server never sees plaintext.
- `apns_tokens(account_id, token, updated_at)`.

## Notes

- Rate-limit `/v1/register` and `/v1/username/available` aggressively; both
  are the only unauthenticated endpoints.
- Never log the auth key or the recovery code. Log only account_id +
  correlation IDs.
