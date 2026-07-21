# OPSEC-Messangar

A privacy-first messenger. iOS first, Android later. All traffic routed
through Tor. Self-hosted backend on a Linux VPS.

- No phone number, no email, no password.
- Account = a 64-character recovery code (shown once, save it).
- Add friends by username.
- Text, images, voice/video calls, push notifications.

## Quick start (iOS)

```bash
brew install xcodegen
cd ios
xcodegen generate
open OPSECMessenger.xcodeproj
```

See [CLAUDE.md](./CLAUDE.md) for architecture, conventions, and the
current punch list.

## Backend

Not implemented yet — see [`backend/api-spec.md`](./backend/api-spec.md)
for the contract the iOS app expects. All backend touchpoints in the iOS
app are placeholders in
[`ios/OPSECMessenger/Config/BackendConfig.swift`](./ios/OPSECMessenger/Config/BackendConfig.swift).
