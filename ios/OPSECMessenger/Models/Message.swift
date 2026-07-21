import Foundation

enum MessageType: String, Codable {
    case text, image, callInvite, systemNotice
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
}
