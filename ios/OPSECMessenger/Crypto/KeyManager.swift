import Foundation
import CryptoKit

/// Placeholder for real end-to-end encryption. In production this should be
/// backed by libsignal (Signal Protocol) or an equivalent double-ratchet
/// implementation. For now it wraps CryptoKit primitives so the rest of the
/// app can call encrypt / decrypt without churning later.
enum KeyManager {
    static func encrypt(plaintext: Data, sharedSecret: SymmetricKey) throws -> Data {
        let sealed = try AES.GCM.seal(plaintext, using: sharedSecret)
        return sealed.combined ?? Data()
    }

    static func decrypt(ciphertext: Data, sharedSecret: SymmetricKey) throws -> Data {
        let box = try AES.GCM.SealedBox(combined: ciphertext)
        return try AES.GCM.open(box, using: sharedSecret)
    }

    /// TODO(crypto): replace with a real per-conversation key derived from
    /// Signal Protocol session state.
    static func placeholderConversationKey(for conversationId: String) -> SymmetricKey {
        let digest = SHA256.hash(data: Data(conversationId.utf8))
        return SymmetricKey(data: digest)
    }
}
