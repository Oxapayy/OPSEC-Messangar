import SwiftUI

struct WelcomeView: View {
    let onRegister: () -> Void
    let onLogin: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("OPSEC").font(.system(size: 44, weight: .heavy))
            Text("Private messaging over Tor.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(spacing: 12) {
                Button(action: onRegister) {
                    Text("Create account")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.borderedProminent)

                Button(action: onLogin) {
                    Text("I already have a code")
                        .frame(maxWidth: .infinity).padding()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .navigationBarHidden(true)
    }
}
