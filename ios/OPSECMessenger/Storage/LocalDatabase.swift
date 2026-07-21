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
}
