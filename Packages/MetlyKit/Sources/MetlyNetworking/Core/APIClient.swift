import Foundation

/// URLSession-based HTTP client for the Metly API.
///
/// - Bearer auth from a `SessionStore`, proactive refresh shortly before expiry.
/// - Single-flight token refresh on `401` (concurrent requests share one `POST /v1/auth/refresh`),
///   then the original request is replayed once.
/// - Retries replayable requests (GET/PUT/DELETE, or POST/PATCH with an `Idempotency-Key`) on
///   timeouts, 5xx and short 429s with exponential backoff; offline fails fast.
/// - `send` is `@concurrent`: encoding/decoding never runs on the main actor.
public final class APIClient: Sendable {
    public let baseURL: URL
    let transport: HTTPTransport
    let refresher: TokenRefresher

    /// - Parameter onSessionInvalidated: called (on an arbitrary thread) when the refresh token is
    ///   rejected and the session was cleared — the app must route back to sign-in.
    public init(baseURL: URL, sessionStore: any SessionStore, urlSession: URLSession = APIClient.makeURLSession(),
                retryPolicy: RetryPolicy = .default, appVersion: String = APIClient.bundleVersion,
                onSessionInvalidated: @escaping @Sendable () -> Void = {}) {
        self.baseURL = baseURL
        let transport = HTTPTransport(baseURL: baseURL, session: urlSession, retryPolicy: retryPolicy,
                                      defaultHeaders: [
                                          "Accept": "application/json",
                                          "X-Metly-Client": "ios/\(appVersion)",
                                          "Accept-Language": Locale.preferredLanguages.prefix(3).joined(separator: ", "),
                                      ])
        self.transport = transport
        refresher = TokenRefresher(store: sessionStore, onInvalidated: onSessionInvalidated) { refreshToken in
            let endpoint = try Endpoint<SessionTokens>(.post, "/v1/auth/refresh", body: RefreshRequest(refreshToken: refreshToken),
                                                       requiresAuth: false, idempotencyKey: UUID().uuidString)
            return try await transport.send(endpoint, accessToken: nil)
        }
    }

    @concurrent
    public func send<Response: Sendable>(_ endpoint: Endpoint<Response>) async throws -> Response {
        guard endpoint.requiresAuth else { return try await transport.send(endpoint, accessToken: nil) }
        let token = try await refresher.validAccessToken()
        do {
            return try await transport.send(endpoint, accessToken: token)
        } catch APIError.server(status: 401, _) {
            let refreshed = try await refresher.refresh(rejectedAccessToken: token)
            do {
                return try await transport.send(endpoint, accessToken: refreshed.accessToken)
            } catch APIError.server(status: 401, _) {
                throw APIError.unauthorized
            }
        }
    }

    /// A non-expired access token (refreshing if needed) — used by the realtime WebSocket.
    public func validAccessToken() async throws -> String {
        try await refresher.validAccessToken()
    }

    public static func makeURLSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    public static var bundleVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}

/// Builds requests, executes them with the retry policy and maps responses to `APIError`.
struct HTTPTransport: Sendable {
    let baseURL: URL
    let session: URLSession
    let retryPolicy: RetryPolicy
    let defaultHeaders: [String: String]

    func send<Response: Sendable>(_ endpoint: Endpoint<Response>, accessToken: String?) async throws -> Response {
        var attempt = 0
        while true {
            attempt += 1
            do {
                try Task.checkCancellation()
                let request = makeRequest(endpoint, accessToken: accessToken)
                let (data, urlResponse) = try await session.data(for: request)
                guard let response = urlResponse as? HTTPURLResponse else { throw APIError.invalidResponse }
                guard (200..<300).contains(response.statusCode) else {
                    throw Self.error(status: response.statusCode, data: data, response: response)
                }
                do {
                    return try endpoint.decode(data, response)
                } catch {
                    throw APIError.decoding(String(describing: error))
                }
            } catch {
                let apiError = APIError(error)
                guard retryPolicy.shouldRetry(apiError, attempt: attempt, replayable: endpoint.isReplayable) else { throw apiError }
                let retryAfter: TimeInterval? = if case .rateLimited(let seconds) = apiError { seconds } else { nil }
                do {
                    try await Task.sleep(for: retryPolicy.delay(afterAttempt: attempt, retryAfter: retryAfter))
                } catch {
                    throw APIError.cancelled
                }
            }
        }
    }

    func makeRequest<Response>(_ endpoint: Endpoint<Response>, accessToken: String?) -> URLRequest {
        var url = endpoint.absoluteURL ?? baseURL.appending(path: endpoint.path)
        if !endpoint.query.isEmpty { url.append(queryItems: endpoint.query) }
        var request = URLRequest(url: url, timeoutInterval: endpoint.timeout)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        // Presigned storage URLs get no API headers (they'd break the signature).
        if endpoint.absoluteURL == nil {
            for (field, value) in defaultHeaders { request.setValue(value, forHTTPHeaderField: field) }
        }
        for (field, value) in endpoint.headers { request.setValue(value, forHTTPHeaderField: field) }
        if let contentType = endpoint.contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if let key = endpoint.idempotencyKey { request.setValue(key, forHTTPHeaderField: "Idempotency-Key") }
        return request
    }

    static func error(status: Int, data: Data, response: HTTPURLResponse) -> APIError {
        let problem = try? MetlyJSON.makeDecoder().decode(APIProblem.self, from: data)
        if status == 429 { return .rateLimited(retryAfter: retryAfter(response)) }
        return .server(status: status, problem: problem)
    }

    /// `Retry-After` delta-seconds (the contract never sends the HTTP-date form).
    static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        return TimeInterval(value.trimmingCharacters(in: .whitespaces)).map { max(0, $0) }
    }
}
