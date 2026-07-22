import Foundation

struct Conversation: Identifiable, Hashable, Codable {
    let id: String
    let peer: UserProfile
    var lastMessage: Message?
    var unreadCount: Int
    var updatedAt: Date

    /// Deterministic 1:1 conversation id — both parties derive the same id
    /// (and thus the same placeholder key) regardless of who starts the chat.
    static func directId(_ a: UInt64, _ b: UInt64) -> String {
        "dm-\(min(a, b))-\(max(a, b))"
    }

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }
}
