import Foundation

/// All backend touchpoints live here. Fill these in once the VPS is up.
/// The rest of the app should only read from this file — never hardcode a host.
enum BackendConfig {
    /// The VPS's Tor .onion address (v3). Preferred transport.
    static let onionHost = "c6fqkiesnximw4xzcwwtwr3hyemvnwgsxcs3ftg2456ec7sclv3vnmad.onion"

    /// Optional clearnet fallback for development only.
    static let clearnetFallback = ""

    /// REST API port on the backend. Hidden service maps 80 → 127.0.0.1:8080.
    static let apiPort = 80

    /// WebSocket port on the backend. Same hidden service port.
    static let wsPort = 80

    /// SHA-256 pin of the clearnet TLS cert (base64). Only used when
    /// `clearnetFallback` is set. Leave empty to disable pinning.
    /// TODO(backend): pin your certificate for the clearnet fallback.
    static let pinnedCertSHA256 = ""

    /// URL scheme picked based on Tor availability + fallback config.
    static var baseURL: URL {
        if TorManager.shared.isEnabled {
            return URL(string: "http://\(onionHost):\(apiPort)")!
        }
        if !clearnetFallback.isEmpty {
            return URL(string: "https://\(clearnetFallback):\(apiPort)")!
        }
        // Nothing configured — the app will run offline against local stubs.
        return URL(string: "http://127.0.0.1:\(apiPort)")!
    }

    static var webSocketURL: URL {
        if TorManager.shared.isEnabled {
            return URL(string: "ws://\(onionHost):\(wsPort)/ws")!
        }
        if !clearnetFallback.isEmpty {
            return URL(string: "wss://\(clearnetFallback):\(wsPort)/ws")!
        }
        return URL(string: "ws://127.0.0.1:\(wsPort)/ws")!
    }
}
