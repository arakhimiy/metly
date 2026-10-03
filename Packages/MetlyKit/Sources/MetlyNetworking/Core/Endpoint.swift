import Foundation

public enum HTTPMethod: String, Sendable {
    case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE"
}

/// Body-less 2xx responses (`204 No Content`, `202 Accepted`).
public struct EmptyResponse: Codable, Sendable, Hashable {
    public init() {}
}

/// One HTTP call: where it goes, what it sends and how the 2xx body becomes `Response`.
public struct Endpoint<Response: Sendable>: Sendable {
    public var method: HTTPMethod
    /// Path relative to the API base URL, e.g. `/v1/cards`. Ignored when `absoluteURL` is set.
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    public var contentType: String?
    public var headers: [String: String]
    /// Adds `Authorization: Bearer …` and enables refresh-on-401.
    public var requiresAuth: Bool
    /// Sent as `Idempotency-Key`; the same key is reused for every retry of this endpoint value.
    public var idempotencyKey: String?
    /// Presigned upload/asset URLs live outside the API host.
    public var absoluteURL: URL?
    public var timeout: TimeInterval
    public var decode: @Sendable (Data, HTTPURLResponse) throws -> Response

    public init(method: HTTPMethod, path: String, query: [URLQueryItem] = [], body: Data? = nil,
                contentType: String? = nil, headers: [String: String] = [:], requiresAuth: Bool = true,
                idempotencyKey: String? = nil, absoluteURL: URL? = nil, timeout: TimeInterval = 30,
                decode: @escaping @Sendable (Data, HTTPURLResponse) throws -> Response) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
        self.contentType = contentType
        self.headers = headers
        self.requiresAuth = requiresAuth
        self.idempotencyKey = idempotencyKey
        self.absoluteURL = absoluteURL
        self.timeout = timeout
        self.decode = decode
    }

    /// GET/PUT/DELETE are idempotent by definition; POST/PATCH only with an idempotency key.
    public var isReplayable: Bool {
        switch method {
        case .get, .put, .delete: true
        case .post, .patch: idempotencyKey != nil
        }
    }
}

public extension Endpoint where Response: Decodable {
    /// JSON response, no body.
    init(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [], requiresAuth: Bool = true,
         idempotencyKey: String? = nil) {
        self.init(method: method, path: path, query: query, requiresAuth: requiresAuth,
                  idempotencyKey: idempotencyKey, decode: Endpoint.decodeJSON)
    }

    /// JSON request and response.
    init(_ method: HTTPMethod, _ path: String, body: some Encodable, query: [URLQueryItem] = [],
         requiresAuth: Bool = true, idempotencyKey: String? = nil) throws {
        let data: Data
        do { data = try MetlyJSON.makeEncoder().encode(body) } catch { throw APIError.transport("Couldn't encode request: \(error)") }
        self.init(method: method, path: path, query: query, body: data, contentType: "application/json",
                  requiresAuth: requiresAuth, idempotencyKey: idempotencyKey, decode: Endpoint.decodeJSON)
    }

    @Sendable static func decodeJSON(_ data: Data, _ response: HTTPURLResponse) throws -> Response {
        if Response.self == EmptyResponse.self, let empty = EmptyResponse() as? Response { return empty }
        return try MetlyJSON.makeDecoder().decode(Response.self, from: data)
    }
}

public extension Endpoint where Response == Data {
    /// Raw bytes (Wallet pass, asset download).
    static func raw(_ method: HTTPMethod = .get, _ path: String = "", absoluteURL: URL? = nil,
                    accept: String, requiresAuth: Bool = true) -> Endpoint<Data> {
        Endpoint<Data>(method: method, path: path, headers: ["Accept": accept], requiresAuth: requiresAuth,
                       absoluteURL: absoluteURL, timeout: 60) { data, _ in data }
    }
}

/// Retry with exponential backoff + jitter for transient failures of replayable requests.
public struct RetryPolicy: Sendable, Equatable {
    public var maxAttempts: Int
    public var baseDelay: Duration
    public var maxDelay: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .milliseconds(400), maxDelay: Duration = .seconds(8)) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
    }

    public static let `default` = RetryPolicy()
    public static let none = RetryPolicy(maxAttempts: 1)

    /// `attempt` is 1-based (the attempt that just failed).
    func delay(afterAttempt attempt: Int, retryAfter: TimeInterval?) -> Duration {
        if let retryAfter { return min(.seconds(retryAfter), maxDelay) }
        let exponential = baseDelay * (1 << min(attempt - 1, 10))
        let jitter = Double.random(in: 0.8...1.2)
        return min(exponential * jitter, maxDelay)
    }

    func shouldRetry(_ error: APIError, attempt: Int, replayable: Bool) -> Bool {
        guard replayable, attempt < maxAttempts else { return false }
        switch error {
        case .timedOut, .transport: return true
        case .rateLimited(let retryAfter): return (retryAfter ?? 0) <= maxDelay.seconds
        case .server(let status, _): return [500, 502, 503, 504].contains(status)
        default: return false   // offline fails fast: the sync engine waits for connectivity instead.
        }
    }
}

extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds) + TimeInterval(parts.attoseconds) / 1e18
    }
}
