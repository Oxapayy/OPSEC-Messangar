import Foundation
import Combine
import CryptoKit
import UIKit

@MainActor
final class AppState: ObservableObject {
    enum Phase { case launching, onboarding, ready }

    @Published var phase: Phase = .launching
    @Published var account: Account?

    let torManager = TorManager.shared
    let api = APIClient.shared
    let socket = WebSocketClient.shared

    /// Routes realtime socket events into the local store.
    private func attachSocketHandlers() async {
        await socket.setOnEvent { [weak self] event in
            Task { @MainActor in self?.handle(event) }
        }
    }

    /// Which conversation is currently on-screen (nil when the user isn't
    /// inside a chat). Used to suppress a notification for the chat you're
    /// already reading — matches native messenger behavior.
    @Published var activeConversationId: String?

    private func handle(_ event: SocketEvent) {
        switch event {
        case .message(let env):
            deliver(env)
            notifyIncoming(env)
        case .contactRequest(let who):
            Task { await LocalDatabase.shared.refreshContacts() }
            NotificationManager.shared.deliverLocal(
                title: "New friend request",
                body: "@\(who.username) wants to connect")
        case .groupInvite(let g):
            Task { await LocalDatabase.shared.refreshGroups() }
            NotificationManager.shared.deliverLocal(
                title: "Group invite", body: "You were invited to \(g.name)")
        case .groupUpdate, .groupRemoved:
            Task { await LocalDatabase.shared.refreshGroups() }
        case .conversationDeleted(let peerId):
            handleConversationDeleted(peerId: peerId)
        default:
            break
        }
    }

    private func notifyIncoming(_ env: MessageEnvelope) {
        // Don't ping for messages you sent or for the chat you're viewing.
        let me = account.map { String($0.numericId) }
        guard env.senderId != me else { return }
        if UIApplication.shared.applicationState == .active,
           activeConversationId == env.conversationId { return }

        let db = LocalDatabase.shared
        let title: String
        if let g = db.group(env.conversationId) {
            title = "\(g.name) · @\(env.senderUsername ?? "user")"
        } else {
            title = "@\(env.senderUsername ?? "user")"
        }
        let body: String
        switch env.type {
        case .text:          body = "New message"
        case .image:         body = "📷 Sent a photo"
        case .video:         body = "🎬 Sent a video"
        case .voice:         body = "🎤 Voice message"
        case .viewOnceImage: body = "👁 View-once photo"
        case .location:      body = "📍 Shared a location"
        default:             body = "New message"
        }
        NotificationManager.shared.deliverLocal(title: title, body: body)
    }

    private func handleConversationDeleted(peerId: String) {
        guard let me = account?.numericId, let their = UInt64(peerId) else { return }
        let convoId = Conversation.directId(me, their)
        LocalDatabase.shared.clearConversation(convoId)
    }

    private func deliver(_ env: MessageEnvelope) {
        guard let acct = account else { return }
        let db = LocalDatabase.shared

        // Group messages are keyed by the group id and shown in the Groups
        // tab, not the 1:1 chat list — don't synthesize a direct conversation.
        // Ensure the conversation exists — messages from strangers create one
        // (the chat list files it under "Message requests" until added back).
        if !db.isGroup(env.conversationId),
           !db.conversations.contains(where: { $0.id == env.conversationId }) {
            let numeric = UInt64(env.senderId) ?? 0
            let name = (env.senderUsername?.isEmpty == false)
                ? env.senderUsername! : "user\(String(env.senderId.suffix(4)))"
            let peer = UserProfile(id: env.senderId, username: name,
                                   numericId: numeric, publicKey: nil)
            db.upsert(conversation: Conversation(
                id: env.conversationId, peer: peer, lastMessage: nil,
                unreadCount: 0, updatedAt: env.sentAt))
        }

        let key = KeyManager.placeholderConversationKey(for: env.conversationId)
        let isOutgoing = env.senderId == String(acct.numericId)

        switch env.type {
        case .image, .viewOnceImage, .voice, .video:
            // payload = base64(fileId). Show a placeholder immediately, then
            // download + decrypt the bytes in the background.
            let fileId = Data(base64Encoded: env.payload)
                .flatMap { String(data: $0, encoding: .utf8) }
            db.append(message: Message(
                id: env.id, conversationId: env.conversationId,
                senderId: env.senderId, type: env.type,
                text: nil, imageData: nil, sentAt: env.sentAt,
                isOutgoing: isOutgoing, loadingMedia: true))
            guard let fileId else { return }
            Task {
                guard let ct = try? await APIClient.shared.downloadAttachment(fileId: fileId),
                      let bytes = try? KeyManager.decrypt(ciphertext: ct, sharedSecret: key)
                else { return }
                await MainActor.run {
                    if env.type == .voice {
                        LocalDatabase.shared.attachMedia(
                            messageId: env.id, in: env.conversationId, audio: bytes)
                    } else {
                        LocalDatabase.shared.attachMedia(
                            messageId: env.id, in: env.conversationId, image: bytes)
                    }
                }
            }
        default:
            var text: String?
            if let ct = Data(base64Encoded: env.payload),
               let pt = try? KeyManager.decrypt(ciphertext: ct, sharedSecret: key) {
                text = String(data: pt, encoding: .utf8)
            }
            db.append(message: Message(
                id: env.id, conversationId: env.conversationId,
                senderId: env.senderId, type: env.type,
                text: text ?? "[encrypted]", imageData: nil,
                sentAt: env.sentAt, isOutgoing: isOutgoing))
        }
    }

    func bootstrap() async {
        // Block on Tor bootstrap — no clearnet fallback.
        await torManager.start()

        // Even if Tor failed, we still surface the onboarding screen so the
        // user sees the error state from within the app.
        if let acct = KeychainStore.shared.loadAccount() {
            account = acct
            AppState.currentUserId = String(acct.numericId)
            AppState.myUsername = acct.username
            LocalDatabase.shared.load(for: acct.numericId)   // restore saved chats
            APIClient.shared.setSessionToken(acct.sessionToken)
            phase = .ready
            await attachSocketHandlers()
            await CallManager.shared.attach()
            await socket.connect(sessionToken: acct.sessionToken)
            await LocalDatabase.shared.refreshContacts()
            await LocalDatabase.shared.refreshGroups()
        } else {
            phase = .onboarding
        }
    }

    func completeOnboarding(_ acct: Account) async {
        LocalDatabase.shared.wipe()                    // drop any prior account
        LocalDatabase.shared.load(for: acct.numericId) // restore this one's chats
        KeychainStore.shared.saveAccount(acct)
        account = acct
        AppState.currentUserId = String(acct.numericId)
        AppState.myUsername = acct.username
        APIClient.shared.setSessionToken(acct.sessionToken)
        phase = .ready
        await attachSocketHandlers()
        await CallManager.shared.attach()
        await socket.connect(sessionToken: acct.sessionToken)
        await LocalDatabase.shared.refreshContacts()
        await LocalDatabase.shared.refreshGroups()
        // Ask for notification permission the first time an account signs in.
        Task { await NotificationManager.shared.requestAuthorization() }
    }

    func signOut() {
        KeychainStore.shared.clear()
        LocalDatabase.shared.wipe()   // don't leak chats to the next account
        account = nil
        AppState.currentUserId = nil
        APIClient.shared.setSessionToken(nil)
        phase = .onboarding
        Task { await socket.disconnect() }
    }
}
