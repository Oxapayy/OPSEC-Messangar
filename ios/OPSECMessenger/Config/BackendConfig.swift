import Foundation

/// All backend touchpoints live here. Fill these in once the VPS is up.
/// The rest of the app should only read from this file — never hardcode a host.
enum BackendConfig {
    /// The VPS's Tor .onion address (v3). Preferred transport for prod.
    static let onionHost = "c6fqkiesnximw4xzcwwtwr3hyemvnwgsxcs3ftg2456ec7sclv3vnmad.onion"
    static let onionPort = 80

    /// DEV-ONLY clearnet bypass — lets the iOS Simulator (which can't run
    /// Tor.framework reliably) hit the backend directly by IP. Leave empty
    /// for production builds.
    static let devClearnetHost = "45.156.87.16"
    static let devClearnetPort = 8080

    /// URL used based on Tor availability + dev clearnet config.
    static var baseURL: URL {
        if TorManager.shared.isEnabled {
            return URL(string: "http://\(onionHost):\(onionPort)")!
        }
        if !devClearnetHost.isEmpty {
            return URL(string: "http://\(devClearnetHost):\(devClearnetPort)")!
        }
        return URL(string: "http://127.0.0.1:\(onionPort)")!
    }

    static var webSocketURL: URL {
        if TorManager.shared.isEnabled {
            return URL(string: "ws://\(onionHost):\(onionPort)/ws")!
        }
        if !devClearnetHost.isEmpty {
            return URL(string: "ws://\(devClearnetHost):\(devClearnetPort)/ws")!
        }
        return URL(string: "ws://127.0.0.1:\(onionPort)/ws")!
    }
}
