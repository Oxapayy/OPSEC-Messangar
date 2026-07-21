import Foundation

/// Placeholder in-memory store. Swap for GRDB / SQLite.swift once the schema
/// stabilises. All persistence for messages happens through this façade so
/// there's one seam to replace.
@MainActor
final class LocalDatabase: ObservableObject {
    static let shared = LocalDatabase()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [String: [Message]] = [:]  // by conversationId

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
