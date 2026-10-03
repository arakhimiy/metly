import Foundation

/// Error body returned by every non-2xx response (`application/json`):
/// `{ "code": "plan_limit_reached", "message": "…", "requestId": "req_…", "details": { … } }`.
public struct APIProblem: Codable, Sendable, Hashable {
    /// Machine-readable code — see `APIErrorCode`. Unknown codes are kept verbatim.
    public var code: String
    /// Developer-facing English message (not localized; never shown verbatim for 5xx).
    public var message: String
    public var requestID: String?
    /// Field-level validation errors (`field → reason`) or extra context (`limit`, `plan`…).
    public var details: [String: String]?

    public init(code: String, message: String, requestID: String? = nil, details: [String: String]? = nil) {
        self.code = code
        self.message = message
        self.requestID = requestID
        self.details = details
    }

    public init(_ code: APIErrorCode, _ message: String, details: [String: String]? = nil) {
        self.init(code: code.rawValue, message: message, details: details)
    }

    public var knownCode: APIErrorCode? { APIErrorCode(rawValue: code) }
}

/// Stable error codes (wire values). Keep in sync with `components.schemas.ErrorCode` in openapi.yaml.
public enum APIErrorCode: String, Codable, Sendable, CaseIterable {
    case invalidRequest = "invalid_request"
    case validationFailed = "validation_failed"
    case unauthorized
    case tokenExpired = "token_expired"
    case invalidGrant = "invalid_grant"
    case forbidden
    case notFound = "not_found"
    case conflict
    case gone
    case cursorExpired = "cursor_expired"
    case planLimitReached = "plan_limit_reached"
    case proRequired = "pro_required"
    case rateLimited = "rate_limited"
    case idempotencyConflict = "idempotency_conflict"
    case payloadTooLarge = "payload_too_large"
    case unsupportedMediaType = "unsupported_media_type"
    case peerUnavailable = "peer_unavailable"
    case requestExpired = "request_expired"
    case blocked
    case internalError = "internal"
    case serviceUnavailable = "service_unavailable"
}

/// Every failure surfaced by `APIClient`, `LiveMetlyAPI` and `MockMetlyServer`.
public enum APIError: Error, Sendable, Equatable {
    /// No connection (or the device is offline). Safe to retry later; sync queues automatically.
    case offline
    case timedOut
    case cancelled
    /// No session, or the refresh token was rejected. The user must sign in again.
    case unauthorized
    /// Any other non-2xx response.
    case server(status: Int, problem: APIProblem?)
    /// 429 — `retryAfter` seconds from the `Retry-After` header when present.
    case rateLimited(retryAfter: TimeInterval?)
    /// The response body didn't match the contract.
    case decoding(String)
    case transport(String)
    case invalidResponse
    /// The feature needs the real backend (returned by `MockMetlyServer`, e.g. Wallet passes).
    case serverRequired(String)

    public var problem: APIProblem? {
        if case .server(_, let problem) = self { return problem }
        return nil
    }

    public var code: APIErrorCode? { problem?.knownCode }

    public var statusCode: Int? {
        switch self {
        case .server(let status, _): status
        case .unauthorized: 401
        case .rateLimited: 429
        default: nil
        }
    }

    /// Network-level failures where retrying later can succeed (drives sync backoff).
    public var isTransient: Bool {
        switch self {
        case .offline, .timedOut, .transport, .rateLimited: true
        case .server(let status, _): status >= 500
        default: false
        }
    }

    public var isPlanLimit: Bool { code == .planLimitReached || code == .proRequired }

    /// Maps transport errors thrown by URLSession.
    public init(_ error: any Error) {
        if let apiError = error as? APIError {
            self = apiError
        } else if error is CancellationError {
            self = .cancelled
        } else if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff,
                 .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                self = .offline
            case .timedOut: self = .timedOut
            case .cancelled: self = .cancelled
            case .userAuthenticationRequired: self = .unauthorized
            default: self = .transport(urlError.localizedDescription)
            }
        } else if let decodingError = error as? DecodingError {
            self = .decoding(String(describing: decodingError))
        } else {
            self = .transport(error.localizedDescription)
        }
    }
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .offline: "You're offline. Check your connection and try again."
        case .timedOut: "The server took too long to respond. Try again."
        case .cancelled: "The request was cancelled."
        case .unauthorized: "Your session has expired. Sign in again."
        case .rateLimited: "Too many requests. Wait a moment and try again."
        case .serverRequired(let message): message
        case .server(let status, let problem):
            if let problem, status < 500 { problem.message } else { "Something went wrong on our side. Try again later." }
        case .decoding, .invalidResponse: "The server sent an unexpected response."
        case .transport(let message): message
        }
    }
}
