# CLAUDE.md

Guidance for AI assistants (Claude Code, etc.) working in this repository.

## Project

**OPSEC-Messangar** — a privacy-first messenger inspired by Signal.
- iOS first (SwiftUI), Android later.
- All network traffic routed through the **Tor** network.
- Self-hosted backend running on a Linux VPS (not yet implemented — backend
  endpoints, hostnames, keys are placeholders).
- No email / phone / password. Account = a **64-character recovery code**
  (letters + digits + symbols) shown once at registration. Users then pick a
  **username** used for adding friends.
- Every registration mints a fresh random numeric account ID (never reused).

## Repository layout

```
CLAUDE.md                  ← this file
README.md                  ← quick-start for humans
ios/
  project.yml              ← XcodeGen spec (generates .xcodeproj)
  OPSECMessenger/
    App/                   ← app entry point + global state
    Config/                ← BackendConfig.swift — all VPS placeholders live here
    Networking/            ← Tor bootstrap, REST client, WebSocket client
    Crypto/                ← 64-char code + numeric ID generator, keystore
    Models/                ← Codable model types
    Storage/               ← Keychain + on-disk cache
    Features/
      Onboarding/          ← Welcome, Register (shows code), Username, Login
      Chats/               ← Chat list, chat detail, composer, image sending
      Contacts/            ← Add-by-username, contact list
      Calls/               ← Incoming/outgoing call UI (signalling stub)
      Settings/            ← Preferences, Tor status, account export
      Notifications/       ← APNs registration + local delivery
    Resources/             ← Info.plist, Assets.xcassets placeholder
backend/
  README.md                ← spec for the VPS backend (to be implemented later)
  api-spec.md              ← REST + WebSocket contract the iOS app expects
```

## Building the iOS app

The app is defined as an [XcodeGen](https://github.com/yonaskolb/XcodeGen)
spec so no `.xcodeproj` (with its noisy `project.pbxproj`) lives in git.

```bash
brew install xcodegen        # once
cd ios
xcodegen generate            # creates OPSECMessenger.xcodeproj
open OPSECMessenger.xcodeproj
```

Minimum: Xcode 15, iOS 16 deployment target.

### Tor integration

`Networking/TorManager.swift` is wired to expect
[Tor.framework](https://github.com/iCepa/Tor.framework) as a Swift Package.
Until the package is added, `TorManager.isEnabled` returns `false` and the
app falls back to plain `URLSession` — this keeps the project buildable on a
fresh clone. To flip Tor on:

1. In Xcode: File → Add Packages → `https://github.com/iCepa/Tor.framework`.
2. Set `OPSEC_ENABLE_TOR=1` in the scheme's Environment Variables.
3. `TorManager` will bootstrap a SOCKS5 proxy on `127.0.0.1:39050` at launch
   and route all `APIClient` / `WebSocketClient` traffic through it.

### Backend placeholders

Nothing real to talk to yet. Every backend touchpoint lives in
`ios/OPSECMessenger/Config/BackendConfig.swift`:

- `onionHost` — the VPS's `.onion` address
- `clearnetFallback` — optional clearnet host (dev only)
- `apiPort`, `wsPort`
- `pinnedCertSHA256` — cert pin for the clearnet fallback

Endpoints the client calls are documented in `backend/api-spec.md`. When the
VPS is up, fill in `BackendConfig` and implement the routes in that spec.

## Conventions

- **SwiftUI only** — no UIKit view controllers unless a system API requires it.
- **`async`/`await`** for all networking. No completion handlers.
- **Zero force-unwraps** in production paths; use `guard let` / typed errors.
- **Secrets** (recovery code, private keys, session token) go through
  `Storage/KeychainStore.swift` — never `UserDefaults`.
- **Backend placeholders** are annotated `// TODO(backend):` so `grep -R
  "TODO(backend)"` returns the full punch list.
- **No analytics, no third-party SDKs beyond Tor.framework.** Adding any new
  dependency needs an explicit reason in the PR description.
- **Recovery-code UX rule**: the code is displayed exactly once, on the
  Register screen, behind a "I have saved this code" confirmation gate. Never
  echo it in logs, never send it to the backend in plaintext — only a
  server-side-verifiable derivative (Argon2id → auth key) leaves the device.

## Git workflow

- Feature branch for this task: `claude/claude-md-docs-4bapeh`.
- Default branch on the remote will be `main` once seeded.
- Never force-push shared branches; never `--no-verify`.

## What to do next (open work)

1. Stand up the VPS backend per `backend/api-spec.md` (Rust/axum or
   Go/net/http both fine — pick one and document in `backend/README.md`).
2. Add Tor.framework and flip `OPSEC_ENABLE_TOR=1`.
3. Wire up real end-to-end encryption (Signal Protocol / libsignal) — the
   current `Crypto/` module only handles the recovery-code + numeric-ID
   generation, not message encryption. Message payloads are placeholders.
4. Implement push notifications end-to-end (APNs token → backend → wake
   the client over the Tor-tunneled WebSocket).
5. Port to Android (Kotlin + Jetpack Compose) reusing `backend/api-spec.md`.
