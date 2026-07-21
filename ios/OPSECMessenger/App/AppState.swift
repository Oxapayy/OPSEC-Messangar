import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    enum Phase { case launching, onboarding, ready }

    @Published var phase: Phase = .launching
    @Published var account: Account?
    @Published var torStatus: TorManager.Status = .disabled

    let api = APIClient.shared
    let socket = WebSocketClient.shared

    func bootstrap() async {
        await TorManager.shared.start()
        torStatus = TorManager.shared.status

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
