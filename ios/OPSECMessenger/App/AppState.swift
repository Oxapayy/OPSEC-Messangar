import Foundation
import Combine
import CryptoKit

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

    private func handle(_ event: SocketEvent) {
        switch event {
        case .message(let env):
            deliver(env)
        case .contactRequest:
            Task { await LocalDatabase.shared.refreshContacts() }
        default:
            break
        }
    }

    private func deliver(_ env: MessageEnvelope) {
        guard let acct = account else { return }
        let db = LocalDatabase.shared

        // Ensure the conversation exists — messages from strangers create one
        // (the chat list files it under "Message requests" until added back).
        if !db.conversations.contains(where: { $0.id == env.conversationId }) {
            let numeric = UInt64(env.senderId) ?? 0
            let name = (env.senderUsername?.isEmpty == false)
                ? env.senderUsername! : "user\(String(env.senderId.suffix(4)))"
            let peer = UserProfile(id: env.senderId, username: name,
                                   numericId: numeric, publicKey: nil)
            db.upsert(conversation: Conversation(
                id: env.conversationId, peer: peer, lastMessage: nil,
                unreadCount: 0, updatedAt: env.sentAt))
        }

        var text: String?
        if let ct = Data(base64Encoded: env.payload) {
            let key = KeyManager.placeholderConversationKey(for: env.conversationId)
            if let pt = try? KeyManager.decrypt(ciphertext: ct, sharedSecret: key) {
                text = String(data: pt, encoding: .utf8)
            }
        }
        db.append(message: Message(
            id: env.id, conversationId: env.conversationId,
            senderId: env.senderId, type: env.type,
            text: text ?? "[encrypted]", imageData: nil,
            sentAt: env.sentAt,
            isOutgoing: env.senderId == String(acct.numericId)))
    }

    func bootstrap() async {
        // Block on Tor bootstrap — no clearnet fallback.
        await torManager.start()

        // Even if Tor failed, we still surface the onboarding screen so the
        // user sees the error state from within the app.
        if let acct = KeychainStore.shared.loadAccount() {
            account = acct
            AppState.currentUserId = String(acct.numericId)
            APIClient.shared.setSessionToken(acct.sessionToken)
            phase = .ready
            await attachSocketHandlers()
            await socket.connect(sessionToken: acct.sessionToken)
            await LocalDatabase.shared.refreshContacts()
        } else {
            phase = .onboarding
        }
    }

    func completeOnboarding(_ acct: Account) async {
        KeychainStore.shared.saveAccount(acct)
        account = acct
        AppState.currentUserId = String(acct.numericId)
        APIClient.shared.setSessionToken(acct.sessionToken)
        phase = .ready
        await attachSocketHandlers()
        await socket.connect(sessionToken: acct.sessionToken)
        await LocalDatabase.shared.refreshContacts()
    }

    func signOut() {
        KeychainStore.shared.clear()
        account = nil
        AppState.currentUserId = nil
        APIClient.shared.setSessionToken(nil)
        phase = .onboarding
        Task { await socket.disconnect() }
    }
}
