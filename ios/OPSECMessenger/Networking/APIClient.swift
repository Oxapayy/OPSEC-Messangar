import Foundation

enum APIError: Error, LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .notConfigured:  return "Backend is not configured yet."
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .decoding(let e): return "Decoding error: \(e.localizedDescription)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

/// Thin REST client. All routes documented in backend/api-spec.md.
/// TODO(backend): all endpoint responses are placeholders until the VPS is up.
final class APIClient {
    static let shared = APIClient()

    private var session: URLSession { TorManager.shared.urlSession() }
    private var sessionToken: String?

    func setSessionToken(_ token: String?) { self.sessionToken = token }

    // MARK: - Auth

    /// POST /v1/register
    /// Body: { authKey: <hex>, numericId: <int> }
    /// Returns the server-issued session token.
    func register(authKey: String, numericId: UInt64) async throws -> String {
        let body: [String: Any] = ["authKey": authKey, "numericId": numericId]
        let resp: RegisterResponse = try await post("/v1/register", body: body, authed: false)
        return resp.sessionToken
    }

    /// POST /v1/login
    /// Body: { authKey: <hex> }
    func login(authKey: String) async throws -> LoginResponse {
        let body = ["authKey": authKey]
        return try await post("/v1/login", body: body, authed: false)
    }

    /// PUT /v1/username
    func claimUsername(_ username: String) async throws {
        let body = ["username": username]
        let _: EmptyResponse = try await put("/v1/username", body: body, authed: true)
    }

    /// GET /v1/username/available?u=foo
    func checkUsernameAvailable(_ username: String) async throws -> Bool {
        let resp: AvailabilityResponse = try await get(
            "/v1/username/available?u=\(username)", authed: false)
        return resp.available
    }

    // MARK: - Contacts

    /// GET /v1/users/lookup?username=foo
    func lookupUser(username: String) async throws -> UserProfile {
        try await get("/v1/users/lookup?username=\(username)", authed: true)
    }

    /// POST /v1/contacts
    func addContact(userId: String) async throws {
        let _: EmptyResponse = try await post(
            "/v1/contacts", body: ["userId": userId], authed: true)
    }

    /// GET /v1/contacts
    func listContacts() async throws -> [UserProfile] {
        let resp: ContactsResponse = try await get("/v1/contacts", authed: true)
        return resp.contacts
    }

    // MARK: - Messages

    /// POST /v1/messages  — envelope is opaque ciphertext (base64).
    func sendMessage(conversationId: String, ciphertext: Data, type: MessageType) async throws {
        let body: [String: Any] = [
            "conversationId": conversationId,
            "type": type.rawValue,
            "payload": ciphertext.base64EncodedString(),
        ]
        let _: EmptyResponse = try await post("/v1/messages", body: body, authed: true)
    }

    /// POST /v1/attachments  — returns a presigned upload URL.
    func requestAttachmentUpload(byteCount: Int) async throws -> AttachmentUploadTicket {
        try await post("/v1/attachments", body: ["size": byteCount], authed: true)
    }

    // MARK: - Calls

    /// POST /v1/calls  — signalling only. Media is peer-to-peer via WebRTC.
    func startCall(peerId: String, sdpOffer: String) async throws -> CallSession {
        try await post("/v1/calls",
                       body: ["peerId": peerId, "sdp": sdpOffer],
                       authed: true)
    }

    // MARK: - Privacy signals

    /// POST /v1/privacy/screenshot  — tells the peer that the recipient just
    /// screenshotted a piece of media in this conversation.
    func reportScreenshot(conversationId: String, mediaId: String?) async throws {
        var body: [String: Any] = ["conversationId": conversationId]
        if let mediaId { body["mediaId"] = mediaId }
        let _: EmptyResponse = try await post(
            "/v1/privacy/screenshot", body: body, authed: true)
    }

    // MARK: - Notifications

    /// POST /v1/push/apns
    func registerAPNsToken(_ token: String) async throws {
        let _: EmptyResponse = try await post(
            "/v1/push/apns", body: ["token": token], authed: true)
    }

    // MARK: - HTTP plumbing

    private func request(_ path: String, method: String, authed: Bool,
                         body: [String: Any]? = nil) throws -> URLRequest {
        let url = BackendConfig.baseURL.appendingPathComponent(path)
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authed {
            guard let token = sessionToken else { throw APIError.notConfigured }
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return req
    }

    private func send<T: Decodable>(_ req: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(0, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode,
                                String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        do { return try JSONDecoder.snake.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func get<T: Decodable>(_ path: String, authed: Bool) async throws -> T {
        try await send(try request(path, method: "GET", authed: authed))
    }
    private func post<T: Decodable>(_ path: String, body: [String: Any],
                                    authed: Bool) async throws -> T {
        try await send(try request(path, method: "POST", authed: authed, body: body))
    }
    private func put<T: Decodable>(_ path: String, body: [String: Any],
                                   authed: Bool) async throws -> T {
        try await send(try request(path, method: "PUT", authed: authed, body: body))
    }
}

extension JSONDecoder {
    static let snake: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }()
}

// MARK: - Response DTOs

struct EmptyResponse: Decodable { init() {} init(from decoder: Decoder) throws {} }
struct RegisterResponse: Decodable { let sessionToken: String }
struct LoginResponse: Decodable { let sessionToken: String; let profile: UserProfile }
struct AvailabilityResponse: Decodable { let available: Bool }
struct ContactsResponse: Decodable { let contacts: [UserProfile] }
struct AttachmentUploadTicket: Decodable { let uploadUrl: String; let fileId: String }
struct CallSession: Decodable { let callId: String; let sdpAnswer: String? }
