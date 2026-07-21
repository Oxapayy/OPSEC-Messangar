import SwiftUI

struct ContactsView: View {
    @State private var contacts: [UserProfile] = []
    @State private var loading = true

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            if loading { ProgressView().tint(Theme.cyan) }
            else if contacts.isEmpty {
                VStack(spacing: 14) {
                    BrandLogo(size: 84)
                    Text("No contacts yet")
                        .font(.headline).foregroundStyle(Theme.textPrimary)
                    NavigationLink { AddFriendView() } label: {
                        Text("Add friend").padding(.horizontal, 24)
                    }
                    .buttonStyle(PrimaryButtonStyle()).fixedSize()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(contacts) { c in
                            HStack(spacing: 12) {
                                Circle().fill(Theme.accentGradient)
                                    .frame(width: 40, height: 40)
                                    .overlay(Text(String(c.username.prefix(1)).uppercased())
                                        .foregroundStyle(Theme.onAccent).font(.headline))
                                VStack(alignment: .leading) {
                                    Text("@" + c.username)
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(String(c.numericId))
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                        }
                    }.padding(.horizontal, 12).padding(.top, 8)
                }
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
        .task { await reload() }
    }

    private func reload() async {
        loading = true
        defer { loading = false }
        contacts = (try? await APIClient.shared.listContacts()) ?? []
    }
}
