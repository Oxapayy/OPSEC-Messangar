import Foundation

enum APIError: Error, LocalizedError {
    case notConfigured
    case http(Int, String)
    case decoding(Error)
    case transport(Error)
    case badURL

    var errorDescription: String? {
        switch self {
        case .notConfigured:  return "Not signed in."
        case .badURL:         return "Bad URL."
        case .http(let c, let m): return "HTTP \(c): \(m)"
        case .decoding(let e): return "Decoding error: \(e.localizedDescription)"
        case .transport(let e): return "Network error: \(e.localizedDescription)"
        }
    }
}

/// Thin REST client. All routes documented in backend/api-spec.md.
final class APIClient {
    static let shared = APIClient()

    /// Cached session so we're not building a new URLSession per request.
    private lazy var session: URLSession = TorManager.shared.urlSession()
    private var sessionToken: String?

    func setSessionToken(_ token: String?) { self.sessionToken = token }

    // MARK: - Auth

    func register(authKey: String, numericId: UInt64) async throws -> String {
        let body: [String: Any] = ["auth_key": authKey, "numeric_id": numericId]
        let resp: RegisterResponse = try await post("/v1/register", body: body, authed: false)
        return resp.sessionToken
    }

    func login(authKey: String) async throws -> LoginResponse {
        try await post("/v1/login", body: ["auth_key": authKey], authed: false)
    }

    func claimUsername(_ username: String) async throws {
        let _: EmptyResponse = try await put(
            "/v1/username", body: ["username": username], authed: true)
    }

    func checkUsernameAvailable(_ username: String) async throws -> Bool {
        let resp: AvailabilityResponse = try await get(
            "/v1/username/available", query: ["u": username], authed: false)
        return resp.available
    }

    // MARK: - Contacts

    func lookupUser(username: String) async throws -> UserProfile {
        try await get("/v1/users/lookup", query: ["username": username], authed: true)
    }

    func addContact(userId: String) async throws {
        let _: EmptyResponse = try await post(
            "/v1/contacts", body: ["user_id": userId], authed: true)
    }

    func listContacts() async throws -> [UserProfile] {
        let resp: ContactsResponse = try await get("/v1/contacts", authed: true)
        return resp.contacts
    }

    // MARK: - Messages

    func sendMessage(conversationId: String, recipientNumericId: UInt64,
                     ciphertext: Data, type: MessageType) async throws {
        let body: [String: Any] = [
            "conversation_id": conversationId,
            "recipient_id": String(recipientNumericId),
            "type": type.rawValue,
            "payload": ciphertext.base64EncodedString(),
        ]
        let _: EmptyResponse = try await post("/v1/messages", body: body, authed: true)
    }

    func requestAttachmentUpload(byteCount: Int) async throws -> AttachmentUploadTicket {
        try await post("/v1/attachments", body: ["size": byteCount], authed: true)
    }

    // MARK: - Calls

    func startCall(peerId: String, sdpOffer: String) async throws -> CallSession {
        try await post("/v1/calls",
                       body: ["peer_id": peerId, "sdp": sdpOffer],
                       authed: true)
    }

    // MARK: - Privacy signals

    func reportScreenshot(conversationId: String, mediaId: String?) async throws {
        var body: [String: Any] = ["conversation_id": conversationId]
        if let mediaId { body["media_id"] = mediaId }
        let _: EmptyResponse = try await post(
            "/v1/privacy/screenshot", body: body, authed: true)
    }

    // MARK: - Notifications

    func registerAPNsToken(_ token: String) async throws {
        let _: EmptyResponse = try await post(
            "/v1/push/apns", body: ["token": token], authed: true)
    }

    // MARK: - HTTP plumbing

    private func buildURL(_ path: String, query: [String: String] = [:]) throws -> URL {
        guard var comps = URLComponents(url: BackendConfig.baseURL,
                                        resolvingAgainstBaseURL: false) else {
            throw APIError.badURL
        }
        comps.path = (comps.path == "/" ? "" : comps.path) + path
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else { throw APIError.badURL }
        return url
    }

    private func request(_ path: String, method: String, authed: Bool,
                         body: [String: Any]? = nil,
                         query: [String: String] = [:]) throws -> URLRequest {
        var req = URLRequest(url: try buildURL(path, query: query))
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
        do { (data, response) = try await session.data(for: req) }
        catch { throw APIError.transport(error) }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.http(0, "no response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode,
                                String(data: data, encoding: .utf8) ?? "")
        }
        if T.self == EmptyResponse.self { return EmptyResponse() as! T }
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do { return try JSONDecoder.snake.decode(T.self, from: data) }
        catch { throw APIError.decoding(error) }
    }

    private func get<T: Decodable>(_ path: String,
                                   query: [String: String] = [:],
                                   authed: Bool) async throws -> T {
        try await send(try request(path, method: "GET", authed: authed, query: query))
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
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}

struct EmptyResponse: Decodable {
    init() {}
    init(from decoder: Decoder) throws {}
}
struct RegisterResponse: Decodable { let sessionToken: String }
struct LoginResponse: Decodable { let sessionToken: String; let profile: UserProfile }
struct AvailabilityResponse: Decodable { let available: Bool }
struct ContactsResponse: Decodable { let contacts: [UserProfile] }
struct AttachmentUploadTicket: Decodable { let uploadUrl: String; let fileId: String }
struct CallSession: Decodable { let callId: String; let sdpAnswer: String? }
