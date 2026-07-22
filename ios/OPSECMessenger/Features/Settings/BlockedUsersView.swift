import SwiftUI

struct BlockedUsersView: View {
    @State private var blocked: [UserProfile] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            if loading {
                ProgressView().tint(Theme.cyan)
            } else if blocked.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "hand.raised.slash")
                        .font(.largeTitle).foregroundStyle(Theme.textSecondary)
                    Text("No blocked users")
                        .foregroundStyle(Theme.textPrimary).font(.headline)
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(blocked) { u in
                            HStack(spacing: 12) {
                                Circle().fill(Theme.accentGradient)
                                    .frame(width: 40, height: 40)
                                    .overlay(Text(String(u.username.prefix(1)).uppercased())
                                        .foregroundStyle(Theme.onAccent).font(.headline))
                                VStack(alignment: .leading) {
                                    Text("@" + u.username).foregroundStyle(Theme.textPrimary)
                                    Text(String(u.numericId))
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Button("Unblock") {
                                    Task {
                                        try? await APIClient.shared.unblockUser(numericId: u.numericId)
                                        await reload()
                                    }
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .frame(width: 110)
                            }
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 8)
                }
            }
        }
        .navigationTitle("Blocked users")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        blocked = (try? await APIClient.shared.listBlocked()) ?? []
    }
}
