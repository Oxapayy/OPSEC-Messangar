import SwiftUI

struct ChatListView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var db = LocalDatabase.shared
    @State private var showNewChat = false
    @State private var openChat: Conversation?

    /// Conversations with people in my contact list.
    private var friendChats: [Conversation] {
        db.conversations.filter { db.isContact(numericId: $0.peer.numericId) }
    }
    /// Messages from people who aren't (yet) contacts — the request folder.
    private var strangerChats: [Conversation] {
        db.conversations.filter { !db.isContact(numericId: $0.peer.numericId) }
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if db.conversations.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !strangerChats.isEmpty {
                            sectionHeader("Message requests · non-friends")
                            ForEach(strangerChats) { c in
                                NavigationLink(value: c) {
                                    ConversationRow(conversation: c, isRequest: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if !friendChats.isEmpty {
                            if !strangerChats.isEmpty { sectionHeader("Chats") }
                            ForEach(friendChats) { c in
                                NavigationLink(value: c) { ConversationRow(conversation: c) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
            }
        }
        .navigationTitle("Chats")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: Conversation.self) { c in ChatView(conversation: c) }
        .navigationDestination(item: $openChat) { c in ChatView(conversation: c) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandLogo(size: 28)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { showNewChat = true } label: {
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.cyan)
                }
            }
        }
        .sheet(isPresented: $showNewChat) {
            NewChatSheet { peer in
                showNewChat = false
                if let me = appState.account?.numericId {
                    openChat = db.openConversation(with: peer, myNumericId: me)
                }
            }
        }
        .task { await db.refreshContacts() }
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.caption).foregroundStyle(Theme.textSecondary).tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4).padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            BrandLogo(size: 96)
            Text("No conversations yet")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Start a chat with a contact, or add a friend by username.")
                .foregroundStyle(Theme.textSecondary).font(.footnote)
            Button { showNewChat = true } label: {
                Text("New chat")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 200)
            .padding(.top, 6)
            NavigationLink { AddFriendView() } label: {
                Text("Add friend")
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Contact picker for starting a new conversation.
private struct NewChatSheet: View {
    @StateObject private var db = LocalDatabase.shared
    @Environment(\.dismiss) private var dismiss
    let onPick: (UserProfile) -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                if db.contacts.isEmpty {
                    VStack(spacing: 12) {
                        Text("No contacts yet")
                            .foregroundStyle(Theme.textPrimary).font(.headline)
                        Text("Add a friend first, then start a chat here.")
                            .foregroundStyle(Theme.textSecondary).font(.footnote)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(db.contacts) { c in
                                Button { onPick(c) } label: {
                                    HStack(spacing: 12) {
                                        Circle().fill(Theme.accentGradient)
                                            .frame(width: 40, height: 40)
                                            .overlay(Text(String(c.username.prefix(1)).uppercased())
                                                .foregroundStyle(Theme.onAccent).font(.headline))
                                        Text("@" + c.username)
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    .padding(12)
                                    .background(Theme.surface,
                                                in: RoundedRectangle(cornerRadius: 14))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12).padding(.top, 8)
                    }
                }
            }
            .navigationTitle("New chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.cyan)
                }
            }
        }
        .task { await db.refreshContacts() }
    }
}

struct ConversationRow: View {
    let conversation: Conversation
    var isRequest: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("@" + conversation.peer.username)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    if isRequest {
                        Text("NEW")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange.opacity(0.25)))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Theme.accentGradient))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                Text(conversation.lastMessage?.text ?? "New conversation")
                    .lineLimit(1)
                    .foregroundStyle(Theme.textSecondary)
                    .font(.subheadline)
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.divider, lineWidth: 1))
    }

    private var avatar: some View {
        Circle()
            .fill(Theme.accentGradient)
            .frame(width: 44, height: 44)
            .overlay(
                Text(String(conversation.peer.username.prefix(1)).uppercased())
                    .font(.headline).foregroundStyle(Theme.onAccent)
            )
    }
}
