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

    #if canImport(Tor)
    private var thread: TorThread?
    private var config: TorConfiguration?
    #endif
    private var logPath: String?

    /// Builds an error whose message carries the tail of Tor's own log, so
    /// on-device failures are diagnosable from the splash screen.
    private func torError(_ message: String, code: Int) -> NSError {
        var full = message
        if let logPath,
           let log = try? String(contentsOfFile: logPath, encoding: .utf8),
           !log.isEmpty {
            let tail = log.split(separator: "\n").suffix(4).joined(separator: "\n")
            if !tail.isEmpty { full += "\n\n" + tail }
        }
        return NSError(domain: "TorManager", code: code,
                       userInfo: [NSLocalizedDescriptionKey: full])
    }

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

        // Log to a file. This is also how we track bootstrap progress: rather
        // than fight the control port (which never accepts a connection on
        // iOS here), we simply tail Tor's own log for "Bootstrapped NN%".
        let logPath = dataDir.appendingPathComponent("tor.log").path
        try? FileManager.default.removeItem(atPath: logPath)
        self.logPath = logPath

        let cfg = TorConfiguration()
        cfg.cookieAuthentication = false
        cfg.dataDirectory = dataDir
        cfg.arguments = [
            "--SocksPort", "\(socksHost):\(socksPort)",
            "--AvoidDiskWrites", "1",
            "--ClientOnly", "1",
            "--Log", "notice file \(logPath)",
        ]
        self.config = cfg

        let t = TorThread(configuration: cfg)
        self.thread = t
        t.start()

        await set(status: .bootstrapping, error: nil)

        // Poll Tor's log for progress until it reports 100% (done).
        let deadline = Date().addingTimeInterval(120)
        var sawAnyLog = false
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 400_000_000)
            guard let log = try? String(contentsOfFile: logPath, encoding: .utf8),
                  !log.isEmpty else { continue }
            sawAnyLog = true

            if let pct = Self.latestBootstrapPercent(in: log) {
                await set(progress: pct)
                if pct >= 100 {
                    await set(status: .connected, error: nil)
                    return
                }
            }
            // Bail out early on a fatal Tor error instead of waiting for timeout.
            if log.contains("[err]") {
                throw torError("Tor reported a fatal error", code: -5)
            }
        }

        throw torError(sawAnyLog ? "bootstrap timeout" : "Tor did not start",
                       code: -3)
    }

    /// Highest "Bootstrapped NN%" value seen in the Tor log so far.
    private static func latestBootstrapPercent(in log: String) -> Int? {
        var best: Int?
        for line in log.split(separator: "\n") {
            guard let r = line.range(of: "Bootstrapped ") else { continue }
            let digits = line[r.upperBound...].prefix { $0.isNumber }
            if let n = Int(digits) { best = max(best ?? 0, n) }
        }
        return best
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
