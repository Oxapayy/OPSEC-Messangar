import Foundation

struct Account: Codable, Equatable {
    let numericId: UInt64
    /// Server-side auth key derived from the recovery code (never the code
    /// itself). Used to re-authenticate.
    let authKey: String
    var username: String?
    var sessionToken: String
    let createdAt: Date
}
