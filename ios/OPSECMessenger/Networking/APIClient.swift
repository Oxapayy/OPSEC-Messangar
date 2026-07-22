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

    /// Cached session, rebuilt whenever Tor's proxy state flips so we never
    /// keep a direct (proxy-less) session after Tor finishes bootstrapping.
    private var _session: URLSession?
    private var _sessionProxied = false
    private var session: URLSession {
        let proxied = TorManager.shared.isEnabled
        if let s = _session, proxied == _sessionProxied { return s }
        let s = TorManager.shared.urlSession()
        _session = s
        _sessionProxied = proxied
        return s
    }
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

    /// People who added me that I haven't added back — the friend-request inbox.
    func listContactRequests() async throws -> [UserProfile] {
        let resp: RequestsResponse = try await get("/v1/contacts/requests", authed: true)
        return resp.requests
    }

    func removeContact(numericId: UInt64) async throws {
        let _: EmptyResponse = try await delete("/v1/contacts/\(numericId)", authed: true)
    }

    func blockUser(numericId: UInt64) async throws {
        let _: EmptyResponse = try await post(
            "/v1/blocks", body: ["user_id": String(numericId)], authed: true)
    }

    func unblockUser(numericId: UInt64) async throws {
        let _: EmptyResponse = try await delete("/v1/blocks/\(numericId)", authed: true)
    }

    func listBlocked() async throws -> [UserProfile] {
        let resp: BlockedResponse = try await get("/v1/blocks", authed: true)
        return resp.blocked
    }

    // MARK: - Groups

    func createGroup(name: String) async throws -> GroupInfo {
        try await post("/v1/groups", body: ["name": name], authed: true)
    }
    func listGroups() async throws -> [GroupInfo] {
        let resp: GroupsResponse = try await get("/v1/groups", authed: true)
        return resp.groups
    }
    func groupDetail(_ id: String) async throws -> GroupInfo {
        try await get("/v1/groups/\(id)", authed: true)
    }
    func listGroupInvites() async throws -> [GroupInfo] {
        let resp: GroupInvitesResponse = try await get("/v1/groups/invites", authed: true)
        return resp.invites
    }
    func inviteToGroup(_ id: String, username: String) async throws {
        let _: EmptyResponse = try await post(
            "/v1/groups/\(id)/invite", body: ["username": username], authed: true)
    }
    func acceptGroupInvite(_ id: String) async throws -> GroupInfo {
        try await post("/v1/groups/\(id)/accept", body: [:], authed: true)
    }
    func declineGroupInvite(_ id: String) async throws {
        let _: EmptyResponse = try await post("/v1/groups/\(id)/decline", body: [:], authed: true)
    }
    func kickFromGroup(_ id: String, numericId: UInt64) async throws {
        let _: EmptyResponse = try await post(
            "/v1/groups/\(id)/kick", body: ["user_id": String(numericId)], authed: true)
    }
    func promoteInGroup(_ id: String, numericId: UInt64) async throws {
        let _: EmptyResponse = try await post(
            "/v1/groups/\(id)/promote", body: ["user_id": String(numericId)], authed: true)
    }
    func leaveGroup(_ id: String) async throws {
        let _: EmptyResponse = try await post("/v1/groups/\(id)/leave", body: [:], authed: true)
    }
    func sendGroupMessage(_ id: String, ciphertext: Data, type: MessageType) async throws {
        let _: EmptyResponse = try await post(
            "/v1/groups/\(id)/messages",
            body: ["type": type.rawValue, "payload": ciphertext.base64EncodedString()],
            authed: true)
    }
    func sendGroupAttachment(_ id: String, fileId: String, type: MessageType) async throws {
        let _: EmptyResponse = try await post(
            "/v1/groups/\(id)/messages",
            body: ["type": type.rawValue, "payload": Data(fileId.utf8).base64EncodedString()],
            authed: true)
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

    /// Uploads raw (already-encrypted) attachment bytes to a ticket's id.
    func uploadAttachment(fileId: String, data: Data) async throws {
        var req = try request("/v1/attachments/\(fileId)", method: "PUT", authed: true)
        req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        let (_, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.http(0, "attachment upload failed")
        }
    }

    /// Downloads raw (still-encrypted) attachment bytes for a file id.
    func downloadAttachment(fileId: String) async throws -> Data {
        let req = try request("/v1/attachments/\(fileId)", method: "GET", authed: true)
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw APIError.http(0, "attachment download failed")
        }
        return data
    }

    /// Sends a media message whose payload is the opaque attachment file id.
    func sendAttachmentMessage(conversationId: String, recipientNumericId: UInt64,
                               fileId: String, type: MessageType) async throws {
        let body: [String: Any] = [
            "conversation_id": conversationId,
            "recipient_id": String(recipientNumericId),
            "type": type.rawValue,
            "payload": Data(fileId.utf8).base64EncodedString(),
        ]
        let _: EmptyResponse = try await post("/v1/messages", body: body, authed: true)
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
    private func delete<T: Decodable>(_ path: String, authed: Bool) async throws -> T {
        try await send(try request(path, method: "DELETE", authed: authed))
    }
}

extension JSONDecoder {
    static let snake: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        // Tolerant ISO8601: accepts timestamps with or without fractional
        // seconds (Go emits fractions; .iso8601 alone rejects them).
        d.dateDecodingStrategy = .custom { dec in
            let s = try dec.singleValueContainer().decode(String.self)
            let f = ISO8601DateFormatter()
            f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = f.date(from: s) { return date }
            f.formatOptions = [.withInternetDateTime]
            if let date = f.date(from: s) { return date }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "unparseable date: \(s)"))
        }
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
struct RequestsResponse: Decodable { let requests: [UserProfile] }
struct BlockedResponse: Decodable { let blocked: [UserProfile] }
struct GroupsResponse: Decodable { let groups: [GroupInfo] }
struct GroupInvitesResponse: Decodable { let invites: [GroupInfo] }
struct AttachmentUploadTicket: Decodable { let uploadUrl: String; let fileId: String }
struct CallSession: Decodable { let callId: String; let sdpAnswer: String? }
