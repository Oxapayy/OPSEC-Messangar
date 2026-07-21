import SwiftUI

@main
struct OPSECMessengerApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Tint UIKit-backed chrome (NavBar / TabBar / TextField cursor) to
        // match the SwiftUI accent so nothing looks out of place.
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

    var body: some View {
        switch appState.phase {
        case .launching: SplashView()
        case .onboarding: OnboardingCoordinator()
        case .ready: MainTabView()
        }
    }
}

struct SplashView: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 24) {
            BrandLogo(size: 140)
                .scaleEffect(pulse ? 1.04 : 1.0)
                .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true),
                           value: pulse)
            Text("OPSEC")
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .tracking(6)
            Text("Private. Onion-routed.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
            ProgressView().tint(Theme.cyan).padding(.top, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        .onAppear { pulse = true }
    }
}
