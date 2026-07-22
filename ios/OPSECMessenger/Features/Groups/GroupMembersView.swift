import SwiftUI

struct GroupMembersView: View {
    let group: GroupInfo
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var db = LocalDatabase.shared
    @State private var showInvite = false
    @State private var confirmLeave = false

    private var live: GroupInfo { db.group(group.id) ?? group }
    private var me: UInt64 { appState.account?.numericId ?? 0 }
    private var iAmAdmin: Bool { live.amIAdmin(me) }
    private var iAmOwner: Bool { live.amIOwner(me) }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 8) {
                    if iAmAdmin {
                        Button { showInvite = true } label: {
                            HStack {
                                Image(systemName: "person.badge.plus")
                                Text("Invite by username")
                                Spacer()
                            }
                            .foregroundStyle(Theme.cyan)
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }

                    ForEach(live.members) { member in memberRow(member) }

                    Button(role: .destructive) { confirmLeave = true } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(iAmOwner ? "Delete group" : "Leave group")
                            Spacer()
                        }
                        .foregroundStyle(.red)
                        .padding(12)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.top, 10)
                }
                .padding(.horizontal, 12).padding(.top, 8)
            }
            .refreshable { await refresh() }
        }
        .navigationTitle("\(live.name) · \(live.members.count)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(isPresented: $showInvite) { InviteToGroupView(group: group) }
        .alert(iAmOwner ? "Delete this group?" : "Leave this group?", isPresented: $confirmLeave) {
            Button("Cancel", role: .cancel) {}
            Button(iAmOwner ? "Delete" : "Leave", role: .destructive) {
                Task {
                    try? await APIClient.shared.leaveGroup(group.id)
                    await db.refreshGroups()
                    dismiss()
                }
            }
        } message: {
            Text(iAmOwner
                 ? "As the creator, leaving disbands the group for everyone."
                 : "You'll stop receiving this group's messages.")
        }
        .task { await refresh() }
    }

    private func memberRow(_ m: GroupMember) -> some View {
        HStack(spacing: 12) {
            Circle().fill(Theme.accentGradient).frame(width: 40, height: 40)
                .overlay(Text(String(m.username.prefix(1)).uppercased())
                    .foregroundStyle(Theme.onAccent).font(.headline))
            VStack(alignment: .leading) {
                Text("@" + m.username).foregroundStyle(Theme.textPrimary)
                Text(m.numericId == me ? "You" : roleLabel(m.role))
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if m.role != "member" {
                Text(m.role.uppercased())
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(m.isOwner ? Theme.cyan.opacity(0.25) : Color.orange.opacity(0.22)))
                    .foregroundStyle(m.isOwner ? Theme.cyan : .orange)
            }
            // Admin actions (never on yourself, never on the owner).
            if iAmAdmin && m.numericId != me && !m.isOwner {
                Menu {
                    if iAmOwner && m.role == "member" {
                        Button {
                            Task { try? await APIClient.shared.promoteInGroup(group.id, numericId: m.numericId)
                                   await refresh() }
                        } label: { Label("Make admin", systemImage: "star") }
                    }
                    // Admins can't kick other admins; the owner can kick anyone but themselves.
                    if iAmOwner || m.role == "member" {
                        Button(role: .destructive) {
                            Task { try? await APIClient.shared.kickFromGroup(group.id, numericId: m.numericId)
                                   await refresh() }
                        } label: { Label("Remove from group", systemImage: "person.badge.minus") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle").foregroundStyle(Theme.cyan)
                }
            }
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
    }

    private func roleLabel(_ r: String) -> String {
        switch r {
        case "owner": return "Creator"
        case "admin": return "Admin"
        default:      return "Member"
        }
    }

    private func refresh() async {
        // Pull the freshest membership; also refreshes the cached groups list.
        if let g = try? await APIClient.shared.groupDetail(group.id) {
            var all = db.groups
            if let i = all.firstIndex(where: { $0.id == g.id }) { all[i] = g }
            db.setGroups(all)
        }
    }
}

struct InviteToGroupView: View {
    let group: GroupInfo
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var status: String?
    @State private var sending = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()
                VStack(spacing: 18) {
                    HStack {
                        Text("@").foregroundStyle(Theme.cyan).font(.title3.bold())
                        TextField("username", text: $username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding()
                    .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.divider, lineWidth: 1))

                    Button {
                        Task { await invite() }
                    } label: {
                        if sending { ProgressView().tint(Theme.onAccent) }
                        else { Text("Send invite") }
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(sending || username.count < 3)

                    if let status {
                        Text(status).font(.footnote)
                            .foregroundStyle(status.hasPrefix("Invited") ? Theme.cyan : .red)
                    }
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Invite to \(group.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.cyan)
                }
            }
        }
    }

    private func invite() async {
        sending = true; defer { sending = false }
        do {
            try await APIClient.shared.inviteToGroup(group.id, username: username)
            status = "Invited @\(username)"
            username = ""
        } catch {
            status = "Could not invite: \(error.localizedDescription)"
        }
    }
}
