import SwiftUI

@main
struct OPSECMessengerApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let cyan = UIColor(Theme.cyan)
        UINavigationBar.appearance().tintColor = cyan
        UITabBar.appearance().tintColor = cyan
        UITextField.appearance().tintColor = cyan
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { await appState.bootstrap() }
                .preferredColorScheme(.dark)
                .tint(Theme.cyan)
                .screenGuard()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject var tor = TorManager.shared

    var body: some View {
        Group {
            switch appState.phase {
            case .launching: SplashView()
            case .onboarding:
                if tor.status == .connected { OnboardingCoordinator() }
                else { SplashView() }
            case .ready: MainTabView()
            }
        }
        // A live call takes over the whole screen, over any tab.
        .overlay { CallOverlay() }
        // Tiny build stamp so we can always confirm which binary is running.
        .overlay(alignment: .bottom) {
            Text("build \(AppInfo.version)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.28))
                .padding(.bottom, 2)
                .allowsHitTesting(false)
        }
    }
}

enum AppInfo {
    static var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        let b = info?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

struct SplashView: View {
    @ObservedObject var tor = TorManager.shared
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 16) {
            BrandLogo(size: 140)
                .scaleEffect(pulse ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: pulse)
            Text("OPSEC")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .tracking(6)

            statusText
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)

            if tor.status == .bootstrapping {
                ProgressView(value: Double(tor.progress), total: 100)
                    .tint(Theme.cyan)
                    .frame(width: 180)
                    .padding(.top, 4)
                Text("\(tor.progress)%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            } else if tor.status == .starting {
                ProgressView().tint(Theme.cyan).padding(.top, 8)
            }

            if let err = tor.lastError, tor.status == .failed {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
                Button("Retry") {
                    Task { await TorManager.shared.start() }
                }
                .buttonStyle(SecondaryButtonStyle())
                .frame(width: 160)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        .onAppear { pulse = true }
    }

    private var statusText: Text {
        switch tor.status {
        case .disabled:      return Text("Preparing Tor…")
        case .starting:      return Text("Starting Tor…")
        case .bootstrapping: return Text("Bootstrapping Tor circuit…")
        case .connected:     return Text("Connected via Tor")
        case .failed:        return Text("Tor bootstrap failed")
        }
    }
}
