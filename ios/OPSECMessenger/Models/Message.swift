import Foundation

enum MessageType: String, Codable {
    case text, image, viewOnceImage, callInvite, systemNotice
}

struct Message: Identifiable, Equatable {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    let text: String?
    let imageData: Data?
    let sentAt: Date
    let isOutgoing: Bool
    /// Set once the recipient has consumed a view-once media. Local-only flag.
    var consumed: Bool = false
}
