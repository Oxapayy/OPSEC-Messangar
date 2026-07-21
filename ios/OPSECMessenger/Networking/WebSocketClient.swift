import Foundation

/// Long-lived, Tor-tunneled socket used for realtime message delivery,
/// call signalling, and presence.
actor WebSocketClient {
    static let shared = WebSocketClient()

    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?

    var onEvent: (@Sendable (SocketEvent) -> Void)?

    func connect(sessionToken: String) async {
        var req = URLRequest(url: BackendConfig.webSocketURL)
        req.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        let session = TorManager.shared.urlSession()
        let t = session.webSocketTask(with: req)
        self.task = t
        t.resume()
        startReceiveLoop()
    }

    func disconnect() async {
        receiveLoop?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func send(_ event: SocketEvent) async throws {
        guard let task else { return }
        let data = try JSONEncoder().encode(event)
        try await task.send(.data(data))
    }

    private func startReceiveLoop() {
        receiveLoop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let task = await self.task else { return }
                do {
                    let msg = try await task.receive()
                    switch msg {
                    case .data(let d): await self.handle(d)
                    case .string(let s): await self.handle(Data(s.utf8))
                    @unknown default: break
                    }
                } catch {
                    // TODO(backend): implement backoff + reconnect.
                    return
                }
            }
        }
    }

    private func handle(_ data: Data) async {
        guard let event = try? JSONDecoder.snake.decode(SocketEvent.self, from: data) else {
            return
        }
        onEvent?(event)
    }
}

enum SocketEvent: Codable {
    case message(MessageEnvelope)
    case typing(conversationId: String, userId: String)
    case callOffer(from: String, sdp: String, callId: String)
    case callAnswer(callId: String, sdp: String)
    case callEnd(callId: String)
    case presence(userId: String, online: Bool)

    // Simple discriminator-based coding.
    enum Kind: String, Codable {
        case message, typing, callOffer, callAnswer, callEnd, presence
    }
    private enum CodingKeys: String, CodingKey { case kind, payload }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .message:    self = .message(try c.decode(MessageEnvelope.self, forKey: .payload))
        case .typing:
            let p = try c.decode([String: String].self, forKey: .payload)
            self = .typing(conversationId: p["conversationId"] ?? "",
                           userId: p["userId"] ?? "")
        case .callOffer:
            let p = try c.decode([String: String].self, forKey: .payload)
            self = .callOffer(from: p["from"] ?? "",
                              sdp: p["sdp"] ?? "",
                              callId: p["callId"] ?? "")
        case .callAnswer:
            let p = try c.decode([String: String].self, forKey: .payload)
            self = .callAnswer(callId: p["callId"] ?? "", sdp: p["sdp"] ?? "")
        case .callEnd:
            let p = try c.decode([String: String].self, forKey: .payload)
            self = .callEnd(callId: p["callId"] ?? "")
        case .presence:
            let p = try c.decode([String: String].self, forKey: .payload)
            self = .presence(userId: p["userId"] ?? "",
                             online: (p["online"] ?? "false") == "true")
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .message(let m):
            try c.encode(Kind.message, forKey: .kind)
            try c.encode(m, forKey: .payload)
        case .typing(let cid, let uid):
            try c.encode(Kind.typing, forKey: .kind)
            try c.encode(["conversationId": cid, "userId": uid], forKey: .payload)
        case .callOffer(let from, let sdp, let callId):
            try c.encode(Kind.callOffer, forKey: .kind)
            try c.encode(["from": from, "sdp": sdp, "callId": callId], forKey: .payload)
        case .callAnswer(let callId, let sdp):
            try c.encode(Kind.callAnswer, forKey: .kind)
            try c.encode(["callId": callId, "sdp": sdp], forKey: .payload)
        case .callEnd(let callId):
            try c.encode(Kind.callEnd, forKey: .kind)
            try c.encode(["callId": callId], forKey: .payload)
        case .presence(let uid, let online):
            try c.encode(Kind.presence, forKey: .kind)
            try c.encode(["userId": uid, "online": String(online)], forKey: .payload)
        }
    }
}

struct MessageEnvelope: Codable, Identifiable {
    let id: String
    let conversationId: String
    let senderId: String
    let type: MessageType
    /// Opaque ciphertext (base64). Decrypted client-side.
    let payload: String
    let sentAt: Date
}
