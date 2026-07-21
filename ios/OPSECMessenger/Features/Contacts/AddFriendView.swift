import SwiftUI

struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var result: UserProfile?
    @State private var searching = false
    @State private var errorText: String?
    @State private var added = false

    var body: some View {
        Form {
            Section("Find by username") {
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit { Task { await search() } }

                Button {
                    Task { await search() }
                } label: {
                    if searching { ProgressView() }
                    else { Text("Search") }
                }
                .disabled(username.count < 3)
            }

            if let result {
                Section("Found") {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("@" + result.username).font(.headline)
                            Text(String(result.numericId))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(added ? "Added" : "Add") {
                            Task { await add(result) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(added)
                    }
                }
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
        }
        .navigationTitle("Add friend")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func search() async {
        searching = true
        defer { searching = false }
        errorText = nil
        result = nil
        do { result = try await APIClient.shared.lookupUser(username: username) }
        catch { errorText = "No user found or backend unreachable." }
    }

    private func add(_ user: UserProfile) async {
        do {
            try await APIClient.shared.addContact(userId: user.id)
            added = true
        } catch {
            errorText = "Could not add contact."
        }
    }
}
