import Foundation

struct Conversation: Identifiable, Equatable {
    let id: String
    let peer: UserProfile
    var lastMessage: Message?
    var unreadCount: Int
    var updatedAt: Date
}
