import SwiftUI

struct WelcomeView: View {
    let onRegister: () -> Void
    let onLogin: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Theme.backgroundGradient.ignoresSafeArea()

                VStack(spacing: 0) {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 20) {
                            Spacer(minLength: 24)

                            BrandLogo(size: 112)
                                .padding(.top, 12)

                            Text("OPSEC")
                                .font(.system(size: 40, weight: .heavy, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                                .tracking(6)

                            Text("Private messaging over Tor.")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.bottom, 8)

                            VStack(spacing: 16) {
                                featureRow(icon: "lock.shield.fill",
                                           title: "No phone, no email",
                                           body: "Your account is a 64-character code you save yourself.")
                                featureRow(icon: "network",
                                           title: "Onion-routed",
                                           body: "Every request travels through the Tor network.")
                                featureRow(icon: "person.2.fill",
                                           title: "Add by username",
                                           body: "Find friends without leaking your contacts.")
                            }
                            .padding(.horizontal, 24)

                            Spacer(minLength: 20)
                        }
                        .frame(minHeight: geo.size.height - 180)
                    }

                    VStack(spacing: 12) {
                        Button("Create account", action: onRegister)
                            .buttonStyle(PrimaryButtonStyle())
                        Button("I already have a code", action: onLogin)
                            .buttonStyle(SecondaryButtonStyle())
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationBarHidden(true)
    }

    private func featureRow(icon: String, title: String, body: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.cyan)
                .frame(width: 36, height: 36)
                .background(Theme.surfaceElevated, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(body).font(.caption).foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
            Spacer()
        }
    }
}
