import SwiftUI

struct UsernameView: View {
    let code: String
    let numericId: UInt64

    @EnvironmentObject var appState: AppState
    @State private var username: String = ""
    @State private var registering = false
    @State private var status: Status = .idle
    @State private var errorText: String?

    enum Status { case idle, checking, available, taken, invalid }

    private var isFormatValid: Bool {
        username.range(of: "^[a-z0-9_]{3,20}$",
                       options: .regularExpression) != nil
    }

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
                    .keyboardType(.asciiCapable)
                    .foregroundStyle(Theme.textPrimary)
                    .onChange(of: username) { _, new in
                        // Normalize: lowercase, [a-z0-9_] only. Stray keyboard
                        // characters (trailing spaces etc.) silently locked
                        // the form before.
                        let cleaned = new.lowercased().filter {
                            ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "_"
                        }
                        if cleaned != new { username = cleaned; return }
                        validate(cleaned)
                    }
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
            // Gate only on the format. Availability is advisory — the
            // backend enforces uniqueness at register time anyway, and a
            // slow/failed Tor round-trip must not lock the user out here.
            .disabled(registering || !isFormatValid || status == .taken)
            .opacity((isFormatValid && status != .taken) ? 1 : 0.5)

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
        case .idle, .checking: return Theme.divider
        }
    }

    @ViewBuilder private var statusLine: some View {
        switch status {
        case .idle: EmptyView()
        case .checking:
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.8)
                Text("Checking availability…")
            }
            .foregroundStyle(Theme.textSecondary).font(.footnote)
        case .invalid: Label("3–20 chars, a–z 0–9 _", systemImage: "xmark.circle")
                .foregroundStyle(.orange).font(.footnote)
        case .available: Label("Available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.cyan).font(.footnote)
        case .taken: Label("Already taken", systemImage: "xmark.circle")
                .foregroundStyle(.red).font(.footnote)
        }
    }

    private func validate(_ s: String) {
        errorText = nil
        guard isFormatValid else { status = s.isEmpty ? .idle : .invalid; return }
        status = .checking
        Task { await checkAvailability(s) }
    }

    private func checkAvailability(_ s: String) async {
        do {
            let available = try await APIClient.shared.checkUsernameAvailable(s)
            if username == s { status = available ? .available : .taken }
        } catch {
            // Advisory only: report the hiccup but leave the button usable —
            // register() gets the authoritative answer from the backend.
            if username == s {
                status = .idle
                errorText = "Availability check failed: \(error.localizedDescription)"
            }
        }
    }

    private func register() async {
        registering = true
        defer { registering = false }
        errorText = nil
        let authKey = AccountCodeGenerator.deriveAuthKey(from: code)
        do {
            let token = try await APIClient.shared.register(authKey: authKey,
                                                            numericId: numericId)
            APIClient.shared.setSessionToken(token)
            try await APIClient.shared.claimUsername(username)

            let acct = Account(numericId: numericId, authKey: authKey,
                               username: username, sessionToken: token,
                               createdAt: Date())
            await appState.completeOnboarding(acct)
        } catch {
            errorText = "Registration failed: \(error.localizedDescription)"
        }
    }
}
