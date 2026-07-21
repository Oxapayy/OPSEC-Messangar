import Foundation
#if canImport(Tor)
import Tor
#endif

/// Bootstraps an embedded Tor client and exposes a local SOCKS5 proxy that
/// URLSession can route through. Uses iCepa/Tor.framework under the hood.
@MainActor
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
        status = .starting
        lastError = nil

        do {
            try await bootstrap()
        } catch {
            lastError = error.localizedDescription
            status = .failed
        }
        #else
        status = .disabled
        lastError = "Tor.framework not linked in this build."
        #endif
    }

    #if canImport(Tor)

    private func bootstrap() async throws {
        // Data directory under Caches — Tor writes here.
        let caches = FileManager.default.urls(for: .cachesDirectory,
                                              in: .userDomainMask).first!
        let dataDir = caches.appendingPathComponent("tor", isDirectory: true)
        try? FileManager.default.createDirectory(at: dataDir,
                                                 withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700],
                                               ofItemAtPath: dataDir.path)

        let cookiePath = dataDir.appendingPathComponent("control_auth_cookie").path

        let cfg = TorConfiguration()
        cfg.cookieAuthentication = true
        cfg.dataDirectory = dataDir
        cfg.arguments = [
            "--SocksPort", "\(socksHost):\(socksPort)",
            "--ControlPort", "\(socksHost):\(controlPort)",
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

        // Wait a moment for tor to open its ports + write the cookie.
        for _ in 0..<50 {
            if FileManager.default.fileExists(atPath: cookiePath) { break }
            try await Task.sleep(nanoseconds: 200_000_000) // 200 ms
        }
        guard let cookie = try? Data(contentsOf: URL(fileURLWithPath: cookiePath)) else {
            throw NSError(domain: "TorManager", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "control cookie not readable"])
        }

        let ctl = TorController(socketHost: socksHost, port: controlPort)
        self.controller = ctl

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            do {
                try ctl.connect()
                cont.resume()
            } catch {
                cont.resume(throwing: error)
            }
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

        status = .bootstrapping

        // Subscribe to bootstrap progress; complete when we hit 100.
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            var finished = false
            let completion: (String) -> Void = { [weak self] progressStr in
                Task { @MainActor [weak self] in
                    if let p = Int(progressStr) { self?.progress = p }
                    if progressStr == "100" && !finished {
                        finished = true
                        cont.resume()
                    }
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

            // Also poll once in case we missed the event.
            ctl.getInfoForKeys(["status/bootstrap-phase"]) { values in
                if let phase = values.first,
                   let range = phase.range(of: "PROGRESS=") {
                    let after = phase[range.upperBound...]
                    let progressStr = after.prefix { $0.isNumber }
                    completion(String(progressStr))
                }
            }

            // Hard timeout after 90 seconds.
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

        status = .connected
    }

    #endif

    // MARK: - URLSession

    /// URLSession routed through the local SOCKS5 proxy when Tor is up.
    /// Falls back to a plain session otherwise (which will fail for .onion
    /// hostnames — by design).
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
