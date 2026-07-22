import SwiftUI

struct ContactsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var db = LocalDatabase.shared
    @State private var loading = true
    @State private var openChat: Conversation?
    @State private var pendingAccept: Set<UInt64> = []
    @State private var acceptError: String?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            if loading && db.contacts.isEmpty && db.contactRequests.isEmpty {
                ProgressView().tint(Theme.cyan)
            } else if db.contacts.isEmpty && db.contactRequests.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if !db.contactRequests.isEmpty {
                            sectionHeader("Friend requests")
                            ForEach(db.contactRequests) { r in requestRow(r) }
                        }
                        if !db.contacts.isEmpty {
                            sectionHeader("Contacts")
                            ForEach(db.contacts) { c in contactRow(c) }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
                .refreshable { await db.refreshContacts() }
            }
        }
        .navigationTitle("Contacts")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AddFriendView() } label: {
                    Image(systemName: "person.badge.plus").foregroundStyle(Theme.cyan)
                }
            }
        }
        .navigationDestination(item: $openChat) { c in ChatView(conversation: c) }
        .alert("Error", isPresented: .init(
            get: { acceptError != nil }, set: { if !$0 { acceptError = nil } }
        )) { Button("OK", role: .cancel) {} } message: {
            Text(acceptError ?? "")
        }
        .task {
            loading = true
            await db.refreshContacts()
            loading = false
        }
    }

    // MARK: - Rows

    private func contactRow(_ c: UserProfile) -> some View {
        HStack(spacing: 12) {
            avatar(c)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("@" + c.username).foregroundStyle(Theme.textPrimary)
                    if c.trusted { TrustedBadge() }
                }
                Text(String(c.numericId))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { startChat(with: c) } label: {
                Image(systemName: "bubble.left.fill")
                    .foregroundStyle(Theme.cyan).font(.title3)
            }
            .buttonStyle(.plain)
            Button { CallManager.shared.startCall(c) } label: {
                Image(systemName: "phone.fill")
                    .foregroundStyle(Theme.cyan).font(.title3)
                    .padding(.leading, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .contextMenu {
            Button(role: .destructive) {
                Task { try? await APIClient.shared.removeContact(numericId: c.numericId)
                       await db.refreshContacts() }
            } label: { Label("Remove friend", systemImage: "person.badge.minus") }
            Button(role: .destructive) {
                Task { try? await APIClient.shared.blockUser(numericId: c.numericId)
                       await db.refreshContacts() }
            } label: { Label("Block", systemImage: "hand.raised") }
        }
    }

    private func requestRow(_ r: UserProfile) -> some View {
        HStack(spacing: 12) {
            avatar(r)
            VStack(alignment: .leading) {
                HStack(spacing: 4) {
                    Text("@" + r.username).foregroundStyle(Theme.textPrimary)
                    if r.trusted { TrustedBadge() }
                }
                Text("wants to connect")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button {
                accept(r)
            } label: {
                if pendingAccept.contains(r.numericId) {
                    ProgressView().tint(Theme.onAccent)
                } else {
                    Text("Accept")
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .frame(width: 96)
            .disabled(pendingAccept.contains(r.numericId))
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1))
    }

    private func accept(_ r: UserProfile) {
        pendingAccept.insert(r.numericId)
        Task {
            defer { pendingAccept.remove(r.numericId) }
            do {
                try await APIClient.shared.addContact(userId: r.id)
                await db.refreshContacts()
            } catch {
                acceptError = "Could not accept: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Helpers

    private func startChat(with peer: UserProfile) {
        guard let me = appState.account?.numericId else { return }
        openChat = db.openConversation(with: peer, myNumericId: me)
    }

    private func avatar(_ p: UserProfile) -> some View {
        Circle().fill(Theme.accentGradient)
            .frame(width: 40, height: 40)
            .overlay(Text(String(p.username.prefix(1)).uppercased())
                .foregroundStyle(Theme.onAccent).font(.headline))
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.caption).foregroundStyle(Theme.textSecondary).tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4).padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            BrandLogo(size: 84)
            Text("No contacts yet")
                .font(.headline).foregroundStyle(Theme.textPrimary)
            NavigationLink { AddFriendView() } label: {
                Text("Add friend")
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(width: 200)
        }
    }
}
