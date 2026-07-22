import Foundation
import SwiftUI
import CryptoKit
import PhotosUI

/// A "Secret Chat" is entirely socket-relayed, never persisted, and disposed
/// of the moment either side taps Leave. Messages travel as `secretMessage`
/// frames (not envelopes) so the server never stores them.
@MainActor
final class SecretChatManager: ObservableObject {
    static let shared = SecretChatManager()

    struct Session: Equatable {
        var id: String
        var peer: UserProfile
        /// I'm the inviter — waiting for the peer to Join.
        var pendingOutgoing: Bool = false
    }

    struct Msg: Identifiable, Equatable {
        let id: String
        let fromMe: Bool
        let text: String?
        let imageData: Data?
        let at: Date
    }

    @Published var incoming: Session?           // ring / "Join secret chat"
    @Published var active: Session?             // the currently-open popup
    @Published var messages: [Msg] = []

    private var myId: UInt64 { UInt64(AppState.currentUserId ?? "") ?? 0 }
    private var myName: String { AppState.myUsername ?? "user" }

    private init() {}

    func attach() async {
        await WebSocketClient.shared.addCallHandler { [weak self] frame in
            guard let kind = frame["kind"] as? String, kind.hasPrefix("secret") else { return }
            Task { @MainActor in self?.handle(frame) }
        }
    }

    // MARK: - Local actions

    func invite(peer: UserProfile) {
        // Fresh random session id — doubles as the shared-key derivation seed.
        let sid = "secret-" + UUID().uuidString.prefix(16).lowercased()
        active = Session(id: sid, peer: peer, pendingOutgoing: true)
        messages = []
        Task {
            await frame("secretInvite", peer: peer.numericId,
                        extra: ["session_id": sid, "from_username": myName])
        }
    }

    func acceptIncoming() {
        guard var s = incoming else { return }
        s.pendingOutgoing = false
        active = s
        incoming = nil
        messages = []
        Task { await frame("secretJoin", peer: s.peer.numericId,
                           extra: ["session_id": s.id]) }
    }

    func declineIncoming() {
        if let s = incoming {
            Task { await frame("secretDecline", peer: s.peer.numericId,
                               extra: ["session_id": s.id]) }
        }
        incoming = nil
    }

    /// Local Leave: wipe on both sides.
    func leave() {
        if let s = active {
            Task { await frame("secretLeave", peer: s.peer.numericId,
                               extra: ["session_id": s.id]) }
        }
        wipe()
    }

    func sendText(_ text: String) {
        guard let s = active, !s.pendingOutgoing, !text.isEmpty else { return }
        let id = UUID().uuidString
        messages.append(Msg(id: id, fromMe: true, text: text,
                            imageData: nil, at: Date()))
        Task { await sendPayload(session: s, kind: "text", text: text, image: nil) }
    }

    func sendImage(_ data: Data) {
        guard let s = active, !s.pendingOutgoing else { return }
        let id = UUID().uuidString
        messages.append(Msg(id: id, fromMe: true, text: nil,
                            imageData: data, at: Date()))
        Task { await sendPayload(session: s, kind: "image", text: nil, image: data) }
    }

    // MARK: - Incoming frames

    private func handle(_ f: [String: Any]) {
        guard let kind = f["kind"] as? String,
              let p = f["payload"] as? [String: Any] else { return }
        let fromStr = (p["from"] as? String) ?? ""
        let from = UInt64(fromStr) ?? 0
        let sid = (p["session_id"] as? String) ?? ""

        switch kind {
        case "secretInvite":
            guard active == nil, incoming == nil else {
                // Busy — auto-decline.
                Task { await frame("secretDecline", peer: from,
                                   extra: ["session_id": sid]) }
                return
            }
            let name = (p["from_username"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "user"
            let peer = UserProfile(id: fromStr, username: name, numericId: from,
                                   publicKey: nil, trusted: false)
            incoming = Session(id: sid, peer: peer)
            NotificationManager.shared.deliverLocal(
                title: "Secret chat invite",
                body: "@\(name) wants to start a secret chat")
        case "secretJoin":
            // Peer accepted my invite → session is live.
            if var s = active, s.id == sid { s.pendingOutgoing = false; active = s }
        case "secretDecline", "secretLeave":
            if active?.id == sid || incoming?.id == sid { wipe() }
        case "secretMessage":
            guard let s = active, s.id == sid else { return }
            let mtype = (p["type"] as? String) ?? "text"
            guard let ctB64 = p["data"] as? String,
                  let ct = Data(base64Encoded: ctB64),
                  let pt = try? KeyManager.decrypt(ciphertext: ct,
                                                   sharedSecret: key(for: sid))
            else { return }
            let id = UUID().uuidString
            switch mtype {
            case "image":
                messages.append(Msg(id: id, fromMe: false, text: nil,
                                    imageData: pt, at: Date()))
            default:
                messages.append(Msg(id: id, fromMe: false,
                                    text: String(data: pt, encoding: .utf8) ?? "",
                                    imageData: nil, at: Date()))
            }
        default:
            break
        }
    }

    private func wipe() {
        active = nil
        incoming = nil
        messages = []
    }

    private func sendPayload(session: Session, kind: String,
                             text: String?, image: Data?) async {
        let plain = image ?? (text.map { Data($0.utf8) } ?? Data())
        guard let ct = try? KeyManager.encrypt(plaintext: plain,
                                               sharedSecret: key(for: session.id))
        else { return }
        await frame("secretMessage", peer: session.peer.numericId, extra: [
            "session_id": session.id,
            "type": kind,
            "data": ct.base64EncodedString(),
        ])
    }

    private func key(for sessionId: String) -> SymmetricKey {
        SymmetricKey(data: SHA256.hash(data: Data(sessionId.utf8)))
    }

    private func frame(_ kind: String, peer: UInt64,
                       extra: [String: Any] = [:]) async {
        var payload: [String: Any] = ["peer_id": String(peer), "from": String(myId)]
        payload.merge(extra) { a, _ in a }
        await WebSocketClient.shared.sendRaw(kind: kind, payload: payload)
    }
}

// MARK: - UI

struct SecretChatOverlay: View {
    @StateObject private var mgr = SecretChatManager.shared

    var body: some View {
        Group {
            if mgr.incoming != nil {
                incomingSheet
            } else if mgr.active != nil {
                SecretChatView()
            } else {
                EmptyView()
            }
        }
    }

    private var incomingSheet: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 44)).foregroundStyle(Theme.cyan)
                Text("Join secret chat")
                    .font(.title2.bold()).foregroundStyle(Theme.textPrimary)
                if let p = mgr.incoming?.peer {
                    Text("@\(p.username) invited you to a one-time chat that isn't saved anywhere.")
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 30)
                }
                HStack(spacing: 22) {
                    Button { mgr.declineIncoming() } label: {
                        Image(systemName: "xmark").font(.title).foregroundStyle(.white)
                            .padding(20).background(Circle().fill(.red))
                    }
                    Button { mgr.acceptIncoming() } label: {
                        Image(systemName: "checkmark").font(.title).foregroundStyle(.white)
                            .padding(20).background(Circle().fill(.green))
                    }
                }
                .padding(.top, 8)
            }
            .padding(28)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 22))
            .padding(24)
        }
    }
}

struct SecretChatView: View {
    @StateObject private var mgr = SecretChatManager.shared
    @State private var draft = ""
    @State private var pickerItem: PhotosPickerItem?
    @State private var confirmLeave = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                if let s = mgr.active, s.pendingOutgoing {
                    Spacer()
                    VStack(spacing: 14) {
                        ProgressView().tint(Theme.cyan).controlSize(.large)
                        Text("Waiting for @\(s.peer.username) to join…")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                } else {
                    scroller
                    composer
                }
            }
        }
        .alert("Leave secret chat?", isPresented: $confirmLeave) {
            Button("Cancel", role: .cancel) {}
            Button("Leave", role: .destructive) { mgr.leave() }
        } message: {
            Text("Everything in this chat will be wiped on BOTH devices.")
        }
    }

    private var header: some View {
        HStack {
            Image(systemName: "lock.shield.fill").foregroundStyle(Theme.cyan)
            Text(mgr.active.map { "Secret · @" + $0.peer.username } ?? "Secret")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button { confirmLeave = true } label: {
                Text("Leave").foregroundStyle(.red)
            }
        }
        .padding()
        .background(Theme.surface)
        .overlay(Rectangle().fill(Theme.divider).frame(height: 0.5), alignment: .bottom)
    }

    private var scroller: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(mgr.messages) { m in
                    HStack {
                        if m.fromMe { Spacer(minLength: 40) }
                        VStack(alignment: .leading, spacing: 4) {
                            if let img = m.imageData, let ui = UIImage(data: img) {
                                Image(uiImage: ui).resizable().scaledToFit()
                                    .frame(maxWidth: 220).cornerRadius(10)
                            } else if let t = m.text {
                                Text(t)
                            }
                            Text(m.at, style: .time)
                                .font(.caption2)
                                .foregroundStyle(m.fromMe
                                                 ? Theme.onAccent.opacity(0.75)
                                                 : Theme.textSecondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 16)
                            .fill(m.fromMe ? Theme.bubbleOutgoing : Theme.surfaceElevated))
                        .foregroundStyle(m.fromMe ? Theme.onAccent : Theme.textPrimary)
                        if !m.fromMe { Spacer(minLength: 40) }
                    }
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 8) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Image(systemName: "photo").font(.title2).foregroundStyle(Theme.cyan)
            }
            .onChange(of: pickerItem) { _, item in
                Task {
                    if let data = try? await item?.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            mgr.sendImage(data); pickerItem = nil
                        }
                    }
                }
            }
            TextField("Message", text: $draft, axis: .vertical)
                .lineLimit(1...5).foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(Theme.divider, lineWidth: 1))
            Button {
                let t = draft.trimmingCharacters(in: .whitespaces)
                draft = ""
                mgr.sendText(t)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32)).foregroundStyle(Theme.cyan)
            }
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12).padding(.bottom, 10).padding(.top, 6)
        .background(Theme.surface.opacity(0.9))
        .overlay(Rectangle().fill(Theme.divider).frame(height: 0.5), alignment: .top)
    }
}
