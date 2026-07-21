import SwiftUI

struct ChatListView: View {
    @StateObject private var db = LocalDatabase.shared

    var body: some View {
        Group {
            if db.conversations.isEmpty {
                emptyState
            } else {
                List(db.conversations) { convo in
                    NavigationLink(value: convo) {
                        ConversationRow(conversation: convo)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Chats")
        .navigationDestination(for: Conversation.self) { c in
            ChatView(conversation: c)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AddFriendView() } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No conversations yet").font(.headline)
            Text("Add a friend by username to get started.")
                .foregroundStyle(.secondary)
                .font(.footnote)
            NavigationLink { AddFriendView() } label: {
                Text("Add friend").padding(.horizontal)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
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
                    Text("@" + conversation.peer.username).font(.headline)
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8).padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                }
                Text(conversation.lastMessage?.text ?? "New conversation")
                    .lineLimit(1)
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    private var avatar: some View {
        Circle()
            .fill(Color.accentColor.opacity(0.2))
            .frame(width: 44, height: 44)
            .overlay(
                Text(String(conversation.peer.username.prefix(1)).uppercased())
                    .font(.headline)
            )
    }
}
