import Foundation

/// On-disk, per-account message persistence so a user's chats (including the
/// messages they sent) survive account switches and app restarts. Stored in
/// Application Support with complete file protection (encrypted at rest by
/// iOS while the device is locked).
enum PersistentStore {
    struct Snapshot: Codable {
        var conversations: [Conversation]
        var messages: [String: [Message]]
    }

    private static func fileURL(for accountId: UInt64) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base,
                                                 withIntermediateDirectories: true)
        return base.appendingPathComponent("chats-\(accountId).json")
    }

    static func load(_ accountId: UInt64) -> Snapshot {
        guard let data = try? Data(contentsOf: fileURL(for: accountId)),
              let snap = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return Snapshot(conversations: [], messages: [:])
        }
        return snap
    }

    static func save(_ snapshot: Snapshot, for accountId: UInt64) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL(for: accountId),
                        options: [.atomic, .completeFileProtectionUnlessOpen])
    }

    static func delete(_ accountId: UInt64) {
        try? FileManager.default.removeItem(at: fileURL(for: accountId))
    }
}
