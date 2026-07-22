import Foundation

/// Placeholder in-memory store. Swap for GRDB / SQLite.swift once the schema
/// stabilises. All persistence for messages happens through this façade so
/// there's one seam to replace.
@MainActor
final class LocalDatabase: ObservableObject {
    static let shared = LocalDatabase()

    @Published private(set) var conversations: [Conversation] = []
    @Published private(set) var messages: [String: [Message]] = [:]  // by conversationId
    @Published private(set) var contacts: [UserProfile] = []
    @Published private(set) var contactRequests: [UserProfile] = []
    @Published private(set) var groups: [GroupInfo] = []
    @Published private(set) var groupInvites: [GroupInfo] = []

    /// The account whose chats are currently loaded; drives which on-disk file
    /// we persist to. nil = signed out (in-memory changes aren't saved).
    private var currentAccountId: UInt64?

    /// Loads this account's chats from disk, replacing whatever's in memory.
    /// Call on sign-in / cold launch before connecting the socket.
    func load(for accountId: UInt64) {
        currentAccountId = accountId
        let snap = PersistentStore.load(accountId)
        conversations = snap.conversations
        messages = snap.messages
    }

    /// Writes the current chats to the active account's file. Debounced onto
    /// the next runloop tick so a burst of appends collapses into one write.
    private var savePending = false
    private func persist() {
        guard let id = currentAccountId, !savePending else { return }
        savePending = true
        Task { @MainActor in
            savePending = false
            PersistentStore.save(
                .init(conversations: conversations, messages: messages), for: id)
        }
    }

    func isGroup(_ conversationId: String) -> Bool {
        groups.contains { $0.id == conversationId }
    }
    func group(_ id: String) -> GroupInfo? { groups.first { $0.id == id } }

    func refreshGroups() async {
        if let g = try? await APIClient.shared.listGroups() { groups = g }
        if let i = try? await APIClient.shared.listGroupInvites() { groupInvites = i }
    }

    func setGroups(_ g: [GroupInfo]) { groups = g }

    func isContact(numericId: UInt64) -> Bool {
        contacts.contains { $0.numericId == numericId }
    }

    /// Pulls contacts + friend requests from the backend into the store.
    func refreshContacts() async {
        if let c = try? await APIClient.shared.listContacts() { contacts = c }
        if let r = try? await APIClient.shared.listContactRequests() { contactRequests = r }
    }

    /// Returns the existing 1:1 conversation with `peer`, creating (and
    /// registering) it when this is the first contact.
    func openConversation(with peer: UserProfile, myNumericId: UInt64) -> Conversation {
        let id = Conversation.directId(myNumericId, peer.numericId)
        if let existing = conversations.first(where: { $0.id == id }) { return existing }
        let convo = Conversation(id: id, peer: peer, lastMessage: nil,
                                 unreadCount: 0, updatedAt: Date())
        upsert(conversation: convo)
        return convo
    }

    func upsert(conversation: Conversation) {
        if let i = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations[i] = conversation
        } else {
            conversations.insert(conversation, at: 0)
        }
        persist()
    }

    func append(message: Message) {
        // Ignore exact duplicates (e.g. an envelope re-flushed on reconnect).
        if messages[message.conversationId]?.contains(where: { $0.id == message.id }) == true {
            return
        }
        messages[message.conversationId, default: []].append(message)
        if let i = conversations.firstIndex(where: { $0.id == message.conversationId }) {
            conversations[i].lastMessage = message
            conversations[i].updatedAt = message.sentAt
            if !message.isOutgoing { conversations[i].unreadCount += 1 }
        }
        persist()
    }

    /// Fills in a media message's bytes once download+decrypt finishes.
    func attachMedia(messageId: String, in conversationId: String,
                     image: Data? = nil, audio: Data? = nil, duration: Double = 0) {
        guard var list = messages[conversationId],
              let i = list.firstIndex(where: { $0.id == messageId }) else { return }
        var m = list[i]
        m.loadingMedia = false
        if let image { m.imageData = image }
        if let audio { m.audioData = audio; m.audioDuration = duration }
        list[i] = m
        messages[conversationId] = list
        persist()
    }

    func markRead(_ conversationId: String) {
        guard let i = conversations.firstIndex(where: { $0.id == conversationId }) else { return }
        conversations[i].unreadCount = 0
        persist()
    }

    /// Deletes a single conversation and all its messages from the local store.
    func clearConversation(_ conversationId: String) {
        conversations.removeAll { $0.id == conversationId }
        messages[conversationId] = nil
        persist()
    }

    /// Clears in-memory state on sign-out. On-disk history is kept so the
    /// account's chats come back when they sign in again; only server-fetched
    /// data (contacts/groups) is dropped.
    func wipe() {
        currentAccountId = nil
        conversations = []
        messages = [:]
        contacts = []
        contactRequests = []
        groups = []
        groupInvites = []
    }

    /// Marks a view-once message as consumed and drops its image bytes so it
    /// can't be re-opened from the local cache.
    func markConsumed(messageId: String, in conversationId: String) {
        guard var list = messages[conversationId],
              let i = list.firstIndex(where: { $0.id == messageId }) else { return }
        let old = list[i]
        list[i] = Message(id: old.id,
                          conversationId: old.conversationId,
                          senderId: old.senderId,
                          type: old.type,
                          text: old.text,
                          imageData: nil,
                          sentAt: old.sentAt,
                          isOutgoing: old.isOutgoing,
                          consumed: true)
        messages[conversationId] = list
        persist()
    }
}
