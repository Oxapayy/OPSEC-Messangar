import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var showSignOut = false

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    header
                    section("Network") {
                        row("Tor", value: appState.torStatus.rawValue.capitalized,
                            valueColor: torColor)
                        row("Backend host", value: BackendConfig.onionHost, mono: true)
                    }
                    section("Notifications") {
                        Button {
                            Task { await NotificationManager.shared.requestAuthorization() }
                        } label: {
                            HStack {
                                Text("Enable push notifications")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "bell.badge.fill")
                                    .foregroundStyle(Theme.cyan)
                            }.padding(.vertical, 4)
                        }
                    }
                    section("Account") {
                        Button(role: .destructive) { showSignOut = true } label: {
                            HStack {
                                Text("Sign out")
                                Spacer()
                                Image(systemName: "arrow.right.square")
                            }
                        }
                    }
                    Text("Signing out clears this device. You'll need your 64-character recovery code to sign back in.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal)
                }
                .padding()
            }
        }
        .navigationTitle("Settings")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .alert("Sign out?", isPresented: $showSignOut) {
            Button("Cancel", role: .cancel) {}
            Button("Sign out", role: .destructive) { appState.signOut() }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            BrandLogo(size: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(appState.account?.username.map { "@" + $0 } ?? "—")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("ID \(appState.account.map { String($0.numericId) } ?? "—")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            Spacer()
        }
        .padding()
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(Theme.cyan.opacity(0.25), lineWidth: 1))
    }

    private func section<Content: View>(_ title: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption).foregroundStyle(Theme.textSecondary).tracking(1)
                .padding(.leading, 4)
            VStack(spacing: 10) { content() }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Theme.divider, lineWidth: 1))
        }
    }

    private func row(_ label: String, value: String,
                     valueColor: Color = Theme.textPrimary,
                     mono: Bool = false) -> some View {
        HStack {
            Text(label).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .foregroundStyle(valueColor)
                .font(mono ? .system(.footnote, design: .monospaced) : .footnote)
                .lineLimit(1).truncationMode(.middle)
        }
    }

    private var torColor: Color {
        switch appState.torStatus {
        case .connected: return .green
        case .starting:  return .orange
        case .failed:    return .red
        case .disabled:  return Theme.textSecondary
        }
    }
}
