import Foundation

/// All backend touchpoints live here. Backend is only reachable through
/// the Tor hidden service — no clearnet fallback in production.
enum BackendConfig {
    /// The VPS's Tor .onion address (v3).
    static let onionHost = "c6fqkiesnximw4xzcwwtwr3hyemvnwgsxcs3ftg2456ec7sclv3vnmad.onion"
    static let onionPort = 80

    static var baseURL: URL {
        URL(string: "http://\(onionHost):\(onionPort)")!
    }

    static var webSocketURL: URL {
        URL(string: "ws://\(onionHost):\(onionPort)/ws")!
    }
}
