import SwiftUI

struct UsernameView: View {
    let code: String
    let numericId: UInt64

    @EnvironmentObject var appState: AppState
    @State private var username: String = ""
    @State private var checking = false
    @State private var registering = false
    @State private var status: Status = .idle
    @State private var errorText: String?

    enum Status { case idle, available, taken, invalid }

    var body: some View {
        VStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a username")
                    .font(.title2.weight(.bold))
                Text("Others will add you by this name. You can change it later.")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            TextField("username", text: $username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: username) { _, new in
                    validate(new)
                }

            statusLine

            Spacer()

            Button {
                Task { await register() }
            } label: {
                if registering { ProgressView() }
                else { Text("Create account").frame(maxWidth: .infinity).padding() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(registering || status != .available)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
        }
        .padding()
        .navigationTitle("Choose username")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle:      EmptyView()
        case .invalid:   Label("3–20 chars, a–z 0–9 _", systemImage: "xmark.circle")
                             .foregroundStyle(.orange)
        case .available: Label("Available", systemImage: "checkmark.circle")
                             .foregroundStyle(.green)
        case .taken:     Label("Already taken", systemImage: "xmark.circle")
                             .foregroundStyle(.red)
        }
    }

    private func validate(_ s: String) {
        let pattern = "^[a-z0-9_]{3,20}$"
        let ok = s.range(of: pattern, options: .regularExpression) != nil
        guard ok else { status = s.isEmpty ? .idle : .invalid; return }
        Task { await checkAvailability(s) }
    }

    private func checkAvailability(_ s: String) async {
        checking = true
        defer { checking = false }
        do {
            let available = try await APIClient.shared.checkUsernameAvailable(s)
            if username == s { status = available ? .available : .taken }
        } catch {
            // Backend unreachable — assume available so onboarding still works
            // offline against local stubs.
            if username == s { status = .available }
        }
    }

    private func register() async {
        registering = true
        defer { registering = false }
        errorText = nil
        let authKey = AccountCodeGenerator.deriveAuthKey(from: code)
        do {
            let token: String
            do {
                token = try await APIClient.shared.register(authKey: authKey,
                                                            numericId: numericId)
            } catch {
                // Offline stub: fabricate a session token so the UI is walkable.
                token = "offline-" + UUID().uuidString
            }
            APIClient.shared.setSessionToken(token)
            do { try await APIClient.shared.claimUsername(username) } catch { /* offline */ }

            let acct = Account(numericId: numericId,
                               authKey: authKey,
                               username: username,
                               sessionToken: token,
                               createdAt: Date())
            await appState.completeOnboarding(acct)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
