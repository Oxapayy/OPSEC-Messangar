import Foundation

/// Placeholder in-memory store. Swap for GRDB / SQLite.swift once the schema
/// stabilises. All persistence for messages happens through this façade so
/// there's one seam to replace.
@MainActor
final class LocalDatabase: ObservableObject {
    static let shared = LocalDatabase()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [String: [Message]] = [:]  // by conversationId
    @Published private(set) var contacts: [UserProfile] = []
    @Published private(set) var contactRequests: [UserProfile] = []

    func isContact(numericId: UInt64) -> Bool {
        contacts.contains { $0.numericId == numericId }
    }

    /// Pulls contacts + friend requests from the backend into the store.
    func refreshContacts() async {
        if let c = try? await APIClient.shared.listContacts() { contacts = c }
        if let r = try? await APIClient.shared.listContactRequests() { contactRequests = r }
    }

    /// Returns the existing 1:1 conversation with `peer`, creating (and
    /// registering) it when this is the first contact.
    func openConversation(with peer: UserProfile, myNumericId: UInt64) -> Conversation {
        let id = Conversation.directId(myNumericId, peer.numericId)
        if let existing = conversations.first(where: { $0.id == id }) { return existing }
        let convo = Conversation(id: id, peer: peer, lastMessage: nil,
                                 unreadCount: 0, updatedAt: Date())
        upsert(conversation: convo)
        return convo
    }

    func upsert(conversation: Conversation) {
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
    }

    func append(message: Message) {
        messages[message.conversationId, default: []].append(message)
        if let i = conversations.firstIndex(where: { $0.id == message.conversationId }) {
            conversations[i].lastMessage = message
            conversations[i].updatedAt = message.sentAt
            if !message.isOutgoing { conversations[i].unreadCount += 1 }
        }
    }

    func markRead(_ conversationId: String) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[i].unreadCount = 0
    }

    /// Deletes a single conversation and all its messages from the local store.
    func clearConversation(_ conversationId: String) {
        conversations.removeAll { $0.id == conversationId }
        messages[conversationId] = nil
    }

    /// Wipes ALL local state. Called on sign-out / account switch so one
    /// account's chats never bleed into another's on the same device.
    func wipe() {
        conversations = []
        messages = [:]
        contacts = []
        contactRequests = []
    }

    /// Marks a view-once message as consumed and drops its image bytes so it
    /// can't be re-opened from the local cache.
    func markConsumed(messageId: String, in conversationId: String) {
        guard var list = messages[conversationId],
              let i = list.firstIndex(where: { $0.id == messageId }) else { return }
        let old = list[i]
        list[i] = Message(id: old.id,
                          conversationId: old.conversationId,
                          senderId: old.senderId,
                          type: old.type,
                          text: old.text,
                          imageData: nil,
                          sentAt: old.sentAt,
                          isOutgoing: old.isOutgoing,
                          consumed: true)
        messages[conversationId] = list
    }
}
