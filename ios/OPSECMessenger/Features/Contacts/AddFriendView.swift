import SwiftUI

struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var result: UserProfile?
    @State private var searching = false
    @State private var errorText: String?
    @State private var added = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            VStack(spacing: 20) {
                BrandLogo(size: 64).padding(.top, 12)
                Text("Add by username")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)

                HStack {
                    Text("@").foregroundStyle(Theme.cyan).font(.title3.bold())
                    TextField("username", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .foregroundStyle(Theme.textPrimary)
                        .onSubmit { Task { await search() } }
                }
                .padding()
                .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.divider, lineWidth: 1))

                Button {
                    Task { await search() }
                } label: {
                    if searching { ProgressView().tint(Theme.onAccent) }
                    else { Text("Search") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(username.count < 3)
                .opacity(username.count >= 3 ? 1 : 0.5)

                if let result {
                    HStack {
                        Circle().fill(Theme.accentGradient)
                            .frame(width: 40, height: 40)
                            .overlay(Text(String(result.username.prefix(1)).uppercased())
                                .foregroundStyle(Theme.onAccent))
                        VStack(alignment: .leading) {
                            Text("@" + result.username)
                                .foregroundStyle(Theme.textPrimary)
                            Text(String(result.numericId))
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Button(added ? "Added" : "Add") { Task { await add(result) } }
                            .buttonStyle(SecondaryButtonStyle()).fixedSize()
                            .disabled(added)
                    }
                    .padding(12)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Theme.cyan.opacity(0.3), lineWidth: 1))
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
                Spacer()
            }
            .padding()
        }
        .navigationTitle("Add friend")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func search() async {
        searching = true; defer { searching = false }
        errorText = nil; result = nil
        do { result = try await APIClient.shared.lookupUser(username: username) }
        catch { errorText = "No user found or backend unreachable." }
    }

    private func add(_ user: UserProfile) async {
        do { try await APIClient.shared.addContact(userId: user.id); added = true }
        catch { errorText = "Could not add contact." }
    }
}
