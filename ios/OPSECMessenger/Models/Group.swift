import Foundation

struct GroupMember: Codable, Hashable, Identifiable {
    var id: UInt64 { numericId }
    let numericId: UInt64
    let username: String
    let role: String   // "owner" | "admin" | "member"

    var isOwner: Bool { role == "owner" }
    var isAdmin: Bool { role == "admin" || role == "owner" }
}

struct GroupInfo: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let ownerId: UInt64
    let members: [GroupMember]

    func role(of numericId: UInt64) -> String? {
        members.first { $0.numericId == numericId }?.role
    }
    func amIOwner(_ me: UInt64) -> Bool { ownerId == me }
    func amIAdmin(_ me: UInt64) -> Bool {
        let r = role(of: me); return r == "owner" || r == "admin"
    }
}
