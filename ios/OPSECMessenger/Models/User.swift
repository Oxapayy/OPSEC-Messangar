import Foundation

struct UserProfile: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let numericId: UInt64
    let publicKey: String?
}
