import SwiftUI

@main
struct OPSECMessengerApp: App {
    @StateObject private var appState = AppState()
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .task { await appState.bootstrap() }
                .preferredColorScheme(.dark)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        switch appState.phase {
        case .launching:
            SplashView()
        case .onboarding:
            OnboardingCoordinator()
        case .ready:
            MainTabView()
        }
    }
}

struct SplashView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 64))
            Text("OPSEC").font(.largeTitle.weight(.heavy))
            ProgressView().padding(.top, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
