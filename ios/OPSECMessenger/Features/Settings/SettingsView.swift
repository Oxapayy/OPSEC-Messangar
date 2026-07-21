import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSignOut = false

    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Username", value: appState.account?.username.map { "@" + $0 } ?? "—")
                LabeledContent("Account number", value: appState.account.map { String($0.numericId) } ?? "—")
            }

            Section("Network") {
                HStack {
                    Text("Tor")
                    Spacer()
                    Text(appState.torStatus.rawValue.capitalized)
                        .foregroundStyle(torColor)
                }
                LabeledContent("Backend host", value: BackendConfig.onionHost)
                    .font(.footnote)
            }

            Section("Notifications") {
                Button("Request permission") {
                    Task { await NotificationManager.shared.requestAuthorization() }
                }
            }

            Section {
                Button("Sign out", role: .destructive) { showSignOut = true }
            } footer: {
                Text("Signing out clears this device. You'll need your 64-character recovery code to sign back in.")
            }
        }
        .navigationTitle("Settings")
        .alert("Sign out?", isPresented: $showSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { appState.signOut() }
        }
    }

    private var torColor: Color {
        switch appState.torStatus {
        case .connected: return .green
        case .starting:  return .orange
        case .failed:    return .red
        case .disabled:  return .secondary
        }
    }
}
