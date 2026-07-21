import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var code: String = ""
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 20) {
            BrandLogo(size: 72).padding(.top, 12)
            Text("Enter your 64-character recovery code")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(Theme.cyanSoft)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 160)
                .padding(10)
                .background(Theme.surfaceElevated,
                            in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.cyan.opacity(0.35), lineWidth: 1))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                Task { await login() }
            } label: {
                if loading { ProgressView().tint(Theme.onAccent) }
                else { Text("Sign in") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(loading || trimmed.count != AccountCodeGenerator.length)
            .opacity(trimmed.count == AccountCodeGenerator.length ? 1 : 0.5)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
            Spacer()
        }
        .padding()
        .themedBackground()
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private var trimmed: String { code.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func login() async {
        loading = true
        defer { loading = false }
        errorText = nil
        let authKey = AccountCodeGenerator.deriveAuthKey(from: trimmed)
        do {
            let resp = try await APIClient.shared.login(authKey: authKey)
            APIClient.shared.setSessionToken(resp.sessionToken)
            let acct = Account(numericId: resp.profile.numericId,
                               authKey: authKey,
                               username: resp.profile.username,
                               sessionToken: resp.sessionToken,
                               createdAt: Date())
            await appState.completeOnboarding(acct)
        } catch {
            errorText = "Could not sign in. Check the code or backend connection."
        }
    }
}
