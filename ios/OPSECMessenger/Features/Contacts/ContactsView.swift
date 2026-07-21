import SwiftUI

struct ContactsView: View {
    @State private var contacts: [UserProfile] = []
    @State private var loading = true

    var body: some View {
        Group {
            if loading { ProgressView() }
            else if contacts.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.2").font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("No contacts yet").font(.headline)
                    NavigationLink { AddFriendView() } label: {
                        Text("Add friend").padding(.horizontal)
                    }.buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(contacts) { c in
                    HStack {
                        Circle().fill(Color.accentColor.opacity(0.2))
                            .frame(width: 36, height: 36)
                            .overlay(Text(String(c.username.prefix(1)).uppercased()))
                        VStack(alignment: .leading) {
                            Text("@" + c.username)
                            Text(String(c.numericId)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Contacts")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { AddFriendView() } label: {
                    Image(systemName: "person.badge.plus")
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
