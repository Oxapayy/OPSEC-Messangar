import Foundation

struct Conversation: Identifiable, Hashable {
    let id: String
    let peer: UserProfile
    var lastMessage: Message?
    var unreadCount: Int
    var updatedAt: Date

    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Conversation, rhs: Conversation) -> Bool { lhs.id == rhs.id }
}
