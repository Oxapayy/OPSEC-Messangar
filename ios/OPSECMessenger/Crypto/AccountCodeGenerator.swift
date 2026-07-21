import Foundation
import CryptoKit

/// Generates the 64-character recovery code shown to the user at registration.
/// Alphabet: uppercase + lowercase + digits + symbols (Mullvad-style but longer
/// and with symbols mixed in).
enum AccountCodeGenerator {
    static let length = 64

    private static let alphabet: [Character] = {
        let upper  = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let lower  = Array("abcdefghijklmnopqrstuvwxyz")
        let digits = Array("0123456789")
        // "Sonderzeichen" — a URL-safe-ish symbol set.
        let symbols = Array("!@#$%^&*()-_=+[]{}<>?/.,;:")
        return upper + lower + digits + symbols
    }()

    /// Uniformly random pick over `alphabet` using SecRandomCopyBytes with
    /// rejection sampling to avoid modulo bias.
    static func generate(length: Int = length) -> String {
        precondition(length > 0)
        let n = UInt32(alphabet.count)
        let maxValid = UInt32.max - (UInt32.max % n)
        var out = String(); out.reserveCapacity(length)
        while out.count < length {
            var buf = [UInt8](repeating: 0, count: 4)
            let status = SecRandomCopyBytes(kSecRandomDefault, buf.count, &buf)
            precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
            let v = buf.withUnsafeBytes { $0.load(as: UInt32.self) }
            guard v < maxValid else { continue }
            out.append(alphabet[Int(v % n)])
        }
        return out
    }

    /// Derives a server-side auth key from the recovery code. The server never
    /// sees the code itself — only this derivative.
    ///
    /// NOTE: For production this MUST be replaced with a memory-hard KDF
    /// (Argon2id). SHA-256 is a temporary placeholder to keep the client
    /// buildable without pulling in a native Argon2 dependency.
    static func deriveAuthKey(from code: String) -> String {
        let data = Data(code.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Random numeric account ID, generated at registration time and never
    /// reused. 18-digit range keeps it well below UInt64.max.
    static func generateNumericId() -> UInt64 {
        var v: UInt64 = 0
        withUnsafeMutableBytes(of: &v) { buf in
            _ = SecRandomCopyBytes(kSecRandomDefault, 8, buf.baseAddress!)
        }
        // Clamp to 18 significant digits so it always prints as a 17–18 digit
        // number without leading zero issues.
        let modulus: UInt64 = 1_000_000_000_000_000_000
        let minimum: UInt64 =   100_000_000_000_000_000
        return minimum + (v % (modulus - minimum))
    }
}
