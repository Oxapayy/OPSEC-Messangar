import Foundation
#if canImport(Tor)
import Tor
#endif

/// Bootstraps an embedded Tor client and exposes a local SOCKS5 proxy that
/// URLSession can route through. Uses iCepa/Tor.framework under the hood.
final class TorManager: ObservableObject {
    static let shared = TorManager()

    enum Status: String {
        case disabled, starting, bootstrapping, connected, failed
    }

    @Published private(set) var status: Status = .disabled
    @Published private(set) var progress: Int = 0
    @Published private(set) var lastError: String?

    let socksHost = "127.0.0.1"
    let socksPort: UInt16 = 39050
    let controlPort: UInt16 = 39051

    #if canImport(Tor)
    private var thread: TorThread?
    private var controller: TorController?
    private var config: TorConfiguration?
    #endif

    /// True once bootstrap hit 100% and SOCKS is ready.
    var isEnabled: Bool { status == .connected }

    private init() {}

    // MARK: - Lifecycle

    func start() async {
        #if canImport(Tor)
        guard status == .disabled || status == .failed else { return }
        await set(status: .starting, error: nil)

        do {
            try await bootstrap()
        } catch {
            await set(status: .failed, error: error.localizedDescription)
        }
        #else
        await set(status: .disabled, error: "Tor.framework not linked in this build.")
        #endif
    }

    private func set(status: Status, error: String?) async {
        await MainActor.run {
            self.status = status
            self.lastError = error
        }
    }

    private func set(progress: Int) async {
        await MainActor.run { self.progress = progress }
    }

    #if canImport(Tor)

    private func bootstrap() async throws {
        let caches = FileManager.default.urls(for: .cachesDirectory,
                                              in: .userDomainMask).first!
        let dataDir = caches.appendingPathComponent("tor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir,
                                                 withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                               ofItemAtPath: dataDir.path)

        let cookiePath = dataDir.appendingPathComponent("control_auth_cookie").path
        // Control over a unix domain socket is more reliable on iOS than TCP.
        let controlSocket = dataDir.appendingPathComponent("control.sock")

        let cfg = TorConfiguration()
        cfg.cookieAuthentication = true
        cfg.dataDirectory = dataDir
        cfg.controlSocket = controlSocket
        cfg.arguments = [
            "--SocksPort", "\(socksHost):\(socksPort)",
            "--CookieAuthFile", cookiePath,
            "--DataDirectory", dataDir.path,
            "--AvoidDiskWrites", "1",
            "--ClientOnly", "1",
            "--Log", "notice stdout",
        ]
        self.config = cfg

        let t = TorThread(configuration: cfg)
        self.thread = t
        t.start()

        // Wait for both the control socket AND the cookie to exist.
        for _ in 0..<100 {
            if FileManager.default.fileExists(atPath: controlSocket.path),
               FileManager.default.fileExists(atPath: cookiePath) { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
        guard let cookie = try? Data(contentsOf: URL(fileURLWithPath: cookiePath)) else {
            throw NSError(domain: "TorManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "control cookie not readable"])
        }

        let ctl = TorController(socketURL: controlSocket)
        self.controller = ctl

        // Retry connect — the socket file can exist a beat before it accepts.
        var connected = false
        var lastError: Error?
        for _ in 0..<40 {
            do {
                try ctl.connect()
                connected = true
                break
            } catch {
                lastError = error
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        guard connected else {
            throw lastError ?? NSError(domain: "TorManager", code: -4,
                userInfo: [NSLocalizedDescriptionKey: "control connect failed"])
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            ctl.authenticate(with: cookie) { success, error in
                if success { cont.resume() }
                else {
                    cont.resume(throwing: error ?? NSError(
                        domain: "TorManager", code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "authenticate failed"]))
                }
            }
        }

        await set(status: .bootstrapping, error: nil)

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var finished = false
            let completion: (String) -> Void = { [weak self] progressStr in
                if let p = Int(progressStr) {
                    Task { await self?.set(progress: p) }
                }
                if progressStr == "100" && !finished {
                    finished = true
                    cont.resume()
                }
            }

            _ = ctl.addObserver(forStatusEvents: {
                (type: String, _: String, action: String, arguments: [String: String]?) -> Bool in
                if type == "STATUS_CLIENT", action == "BOOTSTRAP",
                   let progress = arguments?["PROGRESS"] {
                    completion(progress)
                }
                return true
            })

            ctl.getInfoForKeys(["status/bootstrap-phase"]) { values in
                if let phase = values.first,
                   let range = phase.range(of: "PROGRESS=") {
                    let after = phase[range.upperBound...]
                    let progressStr = after.prefix { $0.isNumber }
                    completion(String(progressStr))
                }
            }

            Task {
                try? await Task.sleep(nanoseconds: 90_000_000_000)
                if !finished {
                    finished = true
                    cont.resume(throwing: NSError(
                        domain: "TorManager", code: -3,
                        userInfo: [NSLocalizedDescriptionKey: "bootstrap timeout"]))
                }
            }
        }

        await set(status: .connected, error: nil)
    }

    #endif

    // MARK: - URLSession

    func urlSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 120
        if isEnabled {
            cfg.connectionProxyDictionary = [
                kCFStreamPropertySOCKSProxyHost as String: socksHost,
                kCFStreamPropertySOCKSProxyPort as String: Int(socksPort),
                kCFStreamPropertySOCKSVersion as String: kCFStreamSocketSOCKSVersion5,
            ]
        }
        return URLSession(configuration: cfg)
    }
}
