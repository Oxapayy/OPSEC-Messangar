import Foundation

struct UserProfile: Codable, Identifiable, Hashable {
    let id: String
    let username: String
    let numericId: UInt64
    let publicKey: String?
    var trusted: Bool = false

    // Tolerate older server responses that omit `trusted`.
    enum CodingKeys: String, CodingKey {
        case id, username, numericId, publicKey, trusted
    }
    init(id: String, username: String, numericId: UInt64,
         publicKey: String?, trusted: Bool = false) {
        self.id = id; self.username = username; self.numericId = numericId
        self.publicKey = publicKey; self.trusted = trusted
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        numericId = try c.decode(UInt64.self, forKey: .numericId)
        publicKey = try c.decodeIfPresent(String.self, forKey: .publicKey)
        trusted = (try? c.decodeIfPresent(Bool.self, forKey: .trusted)) ?? false
    }
}
