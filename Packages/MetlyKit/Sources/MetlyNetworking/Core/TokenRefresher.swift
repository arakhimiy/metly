import Foundation

/// Serialises token refreshes: however many requests hit `401` at once, exactly one
/// `POST /v1/auth/refresh` runs and every caller gets its result (refresh tokens are single-use).
actor TokenRefresher {
    typealias RefreshCall = @Sendable (_ refreshToken: String) async throws -> SessionTokens

    private let store: any SessionStore
    private let onInvalidated: @Sendable () -> Void
    private let refreshCall: RefreshCall
    private var inFlight: Task<AuthSession, any Error>?

    init(store: any SessionStore, onInvalidated: @escaping @Sendable () -> Void, refreshCall: @escaping RefreshCall) {
        self.store = store
        self.onInvalidated = onInvalidated
        self.refreshCall = refreshCall
    }

    /// Current access token, refreshed first when it expires within a minute.
    func validAccessToken() async throws -> String {
        if let inFlight { return try await inFlight.value.accessToken }
        guard let session = store.load() else { throw APIError.unauthorized }
        guard session.isExpiring(within: 60) else { return session.accessToken }
        return try await refresh(rejectedAccessToken: session.accessToken).accessToken
    }

    /// Refreshes unless another caller already replaced `rejectedAccessToken`.
    func refresh(rejectedAccessToken: String?) async throws -> AuthSession {
        if let inFlight { return try await inFlight.value }
        guard let session = store.load() else { throw APIError.unauthorized }
        if let rejectedAccessToken, session.accessToken != rejectedAccessToken, !session.isExpiring(within: 0) {
            return session   // someone refreshed while our request was in flight
        }

        let store = store
        let refreshCall = refreshCall
        let onInvalidated = onInvalidated
        // The outcome is decided inside the shared task, so every caller waiting on it gets the
        // same mapped error (not the raw `400/401 invalid_grant`).
        let task = Task<AuthSession, any Error> {
            do {
                let tokens = try await refreshCall(session.refreshToken)
                let updated = session.refreshed(with: tokens)
                try store.save(updated)
                return updated
            } catch {
                let apiError = APIError(error)
                if case .server(let status, _) = apiError, [400, 401, 403].contains(status) {
                    // invalid_grant / revoked / reused refresh token → the session is dead.
                    store.clear()
                    onInvalidated()
                    throw APIError.unauthorized
                }
                throw apiError
            }
        }
        inFlight = task
        defer { inFlight = nil }
        return try await task.value
    }
}
