import SwiftUI

struct LoginView: View {
    @EnvironmentObject var appState: AppState
    @State private var code: String = ""
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Enter your 64-character recovery code")
                .font(.headline)

            TextEditor(text: $code)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(Color.secondary.opacity(0.15)))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            Button {
                Task { await login() }
            } label: {
                if loading { ProgressView() }
                else { Text("Sign in").frame(maxWidth: .infinity).padding() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading || code.trimmingCharacters(in: .whitespacesAndNewlines).count != AccountCodeGenerator.length)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
            Spacer()
        }
        .padding()
        .navigationTitle("Sign in")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func login() async {
        loading = true
        defer { loading = false }
        errorText = nil
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
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
