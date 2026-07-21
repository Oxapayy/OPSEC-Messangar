import SwiftUI

struct ChatListView: View {
    @StateObject private var db = LocalDatabase.shared

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()

            if db.conversations.isEmpty { emptyState }
            else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(db.conversations) { c in
                            NavigationLink(value: c) { ConversationRow(conversation: c) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
            }
        }
        .navigationTitle("Chats")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationDestination(for: Conversation.self) { c in ChatView(conversation: c) }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BrandLogo(size: 28)
            }
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AddFriendView() } label: {
                    Image(systemName: "square.and.pencil").foregroundStyle(Theme.cyan)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            BrandLogo(size: 96)
            Text("No conversations yet")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Add a friend by username to get started.")
                .foregroundStyle(Theme.textSecondary).font(.footnote)
            NavigationLink { AddFriendView() } label: {
                Text("Add friend").padding(.horizontal, 24)
            }
            .buttonStyle(PrimaryButtonStyle())
            .fixedSize()
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("@" + conversation.peer.username)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
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
