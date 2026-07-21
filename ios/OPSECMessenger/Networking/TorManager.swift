import Foundation

/// Wraps Tor.framework. When the framework isn't linked, everything degrades
/// to no-ops and `isEnabled` stays false — the app still runs and just uses
/// plain URLSession. Flip `OPSEC_ENABLE_TOR=1` in the scheme after adding the
/// SwiftPM package (see CLAUDE.md).
final class TorManager {
    static let shared = TorManager()

    enum Status: String { case disabled, starting, connected, failed }

    private(set) var status: Status = .disabled
    private(set) var socksPort: Int = 39050

    var isEnabled: Bool {
        ProcessInfo.processInfo.environment["OPSEC_ENABLE_TOR"] == "1"
            && status == .connected
    }

    func start() async {
        guard ProcessInfo.processInfo.environment["OPSEC_ENABLE_TOR"] == "1" else {
            status = .disabled
            return
        }
        status = .starting
        // TODO(backend): integrate Tor.framework here.
        //
        // import Tor
        //
        // let config = TorConfiguration()
        // config.cookieAuthentication = true
        // config.dataDirectory = FileManager.default.urls(
        //     for: .applicationSupportDirectory, in: .userDomainMask).first!
        //     .appendingPathComponent("tor")
        // config.arguments = [
        //     "--SocksPort", "\(socksPort)",
        //     "--AvoidDiskWrites", "1",
        //     "--ClientOnly", "1",
        // ]
        // let thread = TorThread(configuration: config)
        // thread.start()
        // // Await TorController connection + bootstrap 100% here.
        // status = .connected
        //
        // For now, mark as failed so the fallback path is used.
        status = .failed
    }

    /// A URLSession configured to route through Tor's SOCKS proxy when
    /// available; otherwise a default session.
    func urlSession() -> URLSession {
        let config = URLSessionConfiguration.default
        if isEnabled {
            config.connectionProxyDictionary = [
                "SOCKSEnable": 1,
                "SOCKSProxy": "127.0.0.1",
                "SOCKSPort": socksPort,
            ]
        }
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        return URLSession(configuration: config)
    }
}
