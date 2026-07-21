import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase { case launching, onboarding, ready }

    @Published var phase: Phase = .launching
    @Published var account: Account?

    let torManager = TorManager.shared
    let api = APIClient.shared
    let socket = WebSocketClient.shared

    func bootstrap() async {
        // Block on Tor bootstrap — no clearnet fallback.
        await torManager.start()

        // Even if Tor failed, we still surface the onboarding screen so the
        // user sees the error state from within the app.
        if let acct = KeychainStore.shared.loadAccount() {
            account = acct
            AppState.currentUserId = String(acct.numericId)
            APIClient.shared.setSessionToken(acct.sessionToken)
            phase = .ready
            await socket.connect(sessionToken: acct.sessionToken)
        } else {
            phase = .onboarding
        }
    }

    func completeOnboarding(_ acct: Account) async {
        KeychainStore.shared.saveAccount(acct)
        account = acct
        AppState.currentUserId = String(acct.numericId)
        APIClient.shared.setSessionToken(acct.sessionToken)
        phase = .ready
        await socket.connect(sessionToken: acct.sessionToken)
    }

    func signOut() {
        KeychainStore.shared.clear()
        account = nil
        AppState.currentUserId = nil
        APIClient.shared.setSessionToken(nil)
        phase = .onboarding
        Task { await socket.disconnect() }
    }
}
