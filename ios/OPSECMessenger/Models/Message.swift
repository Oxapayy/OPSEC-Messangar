import Foundation

enum MessageType: String, Codable {
    case text, image, viewOnceImage, voice, callInvite, systemNotice
}

struct Message: Identifiable, Equatable, Codable {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    let text: String?
    var imageData: Data?
    let sentAt: Date
    let isOutgoing: Bool
    /// Set once the recipient has consumed a view-once media. Local-only flag.
    var consumed: Bool = false
    /// Decoded voice-note audio (m4a). Populated after download+decrypt.
    var audioData: Data? = nil
    var audioDuration: Double = 0
    /// While a media message's bytes are still downloading/decrypting.
    var loadingMedia: Bool = false

    /// Short preview for the conversation list.
    var preview: String {
        switch type {
        case .text, .systemNotice: return text ?? ""
        case .image:               return "📷 Photo"
        case .viewOnceImage:       return "👁 View-once photo"
        case .voice:               return "🎤 Voice message"
        case .callInvite:          return "📞 Call"
        }
    }
}
