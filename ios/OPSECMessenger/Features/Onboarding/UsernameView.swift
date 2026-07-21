import SwiftUI

struct UsernameView: View {
    let code: String
    let numericId: UInt64

    @EnvironmentObject var appState: AppState
    @State private var username: String = ""
    @State private var registering = false
    @State private var status: Status = .idle
    @State private var errorText: String?

    enum Status { case idle, available, taken, invalid }

    var body: some View {
        VStack(spacing: 24) {
            BrandLogo(size: 72).padding(.top, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text("Pick a username")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Others will add you by this name. You can change it later.")
                    .foregroundStyle(Theme.textSecondary)
                    .font(.footnote)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Text("@").foregroundStyle(Theme.cyan).font(.title3.weight(.bold))
                TextField("username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .foregroundStyle(Theme.textPrimary)
                    .onChange(of: username) { _, new in validate(new) }
            }
            .padding()
            .background(Theme.surfaceElevated, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(borderColor, lineWidth: 1))

            statusLine

            Spacer()

            Button {
                Task { await register() }
            } label: {
                if registering { ProgressView().tint(Theme.onAccent) }
                else { Text("Create account") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(registering || status != .available)
            .opacity(status == .available ? 1 : 0.5)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
        }
        .padding()
        .themedBackground()
        .navigationTitle("Choose username")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var borderColor: Color {
        switch status {
        case .available: return Theme.cyan
        case .taken, .invalid: return .red.opacity(0.7)
        case .idle: return Theme.divider
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle: EmptyView()
        case .invalid: Label("3–20 chars, a–z 0–9 _", systemImage: "xmark.circle")
                .foregroundStyle(.orange).font(.footnote)
        case .available: Label("Available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.cyan).font(.footnote)
        case .taken: Label("Already taken", systemImage: "xmark.circle")
                .foregroundStyle(.red).font(.footnote)
        }
    }

    private func validate(_ s: String) {
        let pattern = "^[a-z0-9_]{3,20}$"
        let ok = s.range(of: pattern, options: .regularExpression) != nil
        guard ok else { status = s.isEmpty ? .idle : .invalid; return }
        Task { await checkAvailability(s) }
    }

    private func checkAvailability(_ s: String) async {
        do {
            let available = try await APIClient.shared.checkUsernameAvailable(s)
            if username == s { status = available ? .available : .taken }
        } catch {
            if username == s { status = .available }
        }
    }

    private func register() async {
        registering = true
        defer { registering = false }
        errorText = nil
        let authKey = AccountCodeGenerator.deriveAuthKey(from: code)
        let token: String
        do {
            token = try await APIClient.shared.register(authKey: authKey,
                                                        numericId: numericId)
        } catch {
            token = "offline-" + UUID().uuidString
        }
        APIClient.shared.setSessionToken(token)
        do { try await APIClient.shared.claimUsername(username) } catch {}

        let acct = Account(numericId: numericId, authKey: authKey,
                           username: username, sessionToken: token,
                           createdAt: Date())
        await appState.completeOnboarding(acct)
    }
}
