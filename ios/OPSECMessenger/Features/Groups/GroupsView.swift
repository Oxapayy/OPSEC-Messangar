import SwiftUI

struct GroupsView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var db = LocalDatabase.shared
    @State private var showCreate = false
    @State private var pendingJoin: Set<String> = []
    @State private var joinError: String?

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if !db.groupInvites.isEmpty {
                        sectionHeader("Group invites")
                        ForEach(db.groupInvites) { g in inviteRow(g) }
                    }
                    if !db.groups.isEmpty {
                        sectionHeader("Groups")
                        ForEach(db.groups) { g in
                            NavigationLink { GroupChatView(group: g) } label: { groupRow(g) }
                                .buttonStyle(.plain)
                        }
                    }
                    if db.groups.isEmpty && db.groupInvites.isEmpty {
                        emptyState.padding(.top, 60)
                    }
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
            .refreshable { await db.refreshGroups() }
        }
        .navigationTitle("Groups")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showCreate = true } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(Theme.cyan)
                }
            }
        }
        .sheet(isPresented: $showCreate) { CreateGroupView() }
        .alert("Error", isPresented: .init(
            get: { joinError != nil }, set: { if !$0 { joinError = nil } }
        )) { Button("OK", role: .cancel) {} } message: {
            Text(joinError ?? "")
        }
        .task { await db.refreshGroups() }
    }

    private func join(_ g: GroupInfo) {
        pendingJoin.insert(g.id)
        Task {
            defer { pendingJoin.remove(g.id) }
            do {
                _ = try await APIClient.shared.acceptGroupInvite(g.id)
                await db.refreshGroups()
            } catch {
                joinError = "Could not join: \(error.localizedDescription)"
            }
        }
    }

    private func groupRow(_ g: GroupInfo) -> some View {
        HStack(spacing: 12) {
            groupAvatar(g)
            VStack(alignment: .leading, spacing: 2) {
                Text(g.name).font(.headline).foregroundStyle(Theme.textPrimary)
                Text("\(g.members.count) member\(g.members.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider, lineWidth: 1))
    }

    private func inviteRow(_ g: GroupInfo) -> some View {
        HStack(spacing: 12) {
            groupAvatar(g)
            VStack(alignment: .leading) {
                Text(g.name).foregroundStyle(Theme.textPrimary)
                Text("You've been invited").font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button { join(g) } label: {
                if pendingJoin.contains(g.id) {
                    ProgressView().tint(Theme.onAccent)
                } else { Text("Join") }
            }
            .buttonStyle(SecondaryButtonStyle()).frame(width: 76)
            .disabled(pendingJoin.contains(g.id))
            Button {
                Task { try? await APIClient.shared.declineGroupInvite(g.id)
                       await db.refreshGroups() }
            } label: { Image(systemName: "xmark").foregroundStyle(Theme.textSecondary) }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1))
    }

    private func groupAvatar(_ g: GroupInfo) -> some View {
        RoundedRectangle(cornerRadius: 12).fill(Theme.accentGradient)
            .frame(width: 44, height: 44)
            .overlay(Image(systemName: "person.3.fill").foregroundStyle(Theme.onAccent))
    }

    private func sectionHeader(_ t: String) -> some View {
        Text(t.uppercased()).font(.caption).foregroundStyle(Theme.textSecondary).tracking(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 4).padding(.top, 6)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.3.fill").font(.largeTitle).foregroundStyle(Theme.cyan)
            Text("No groups yet").font(.headline).foregroundStyle(Theme.textPrimary)
            Text("Create a group and invite people by username.")
                .font(.footnote).foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }
}

struct CreateGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var db = LocalDatabase.shared
    @State private var name = ""
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 20) {
                    RoundedRectangle(cornerRadius: 18).fill(Theme.accentGradient)
                        .frame(width: 80, height: 80)
                        .overlay(Image(systemName: "person.3.fill").font(.title)
                            .foregroundStyle(Theme.onAccent))
                        .padding(.top, 20)
                    TextField("Group name", text: $name)
                        .textInputAutocapitalization(.words)
                        .foregroundStyle(Theme.textPrimary)
                        .padding()
                        .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider, lineWidth: 1))
                    Button {
                        Task { await create() }
                    } label: {
                        if creating { ProgressView().tint(Theme.onAccent) }
                        else { Text("Create group") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(creating || name.trimmingCharacters(in: .whitespaces).count < 2)
                    if let errorText {
                        Text(errorText).foregroundStyle(.red).font(.footnote)
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("New group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.cyan)
                }
            }
        }
    }

    private func create() async {
        creating = true; defer { creating = false }
        errorText = nil
        do {
            _ = try await APIClient.shared.createGroup(
                name: name.trimmingCharacters(in: .whitespaces))
            await db.refreshGroups()
            dismiss()
        } catch {
            errorText = "Could not create group: \(error.localizedDescription)"
        }
    }
}
