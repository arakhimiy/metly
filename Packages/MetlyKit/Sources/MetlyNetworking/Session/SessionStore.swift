import Foundation
import Synchronization

/// The signed-in user's tokens. Persisted by a `SessionStore` (Keychain in the app).
public struct AuthSession: Codable, Sendable, Hashable {
    public var userID: UUID
    public var email: String?
    /// Short-lived JWT sent as `Authorization: Bearer …`.
    public var accessToken: String
    /// Opaque, single-use (rotated on every refresh).
    public var refreshToken: String
    public var accessTokenExpiresAt: Date

    public init(userID: UUID, email: String?, accessToken: String, refreshToken: String, accessTokenExpiresAt: Date) {
        self.userID = userID
        self.email = email
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accessTokenExpiresAt = accessTokenExpiresAt
    }

    public init(tokens: SessionTokens, user: UserDTO) {
        self.init(userID: user.id, email: user.email, accessToken: tokens.accessToken,
                  refreshToken: tokens.refreshToken, accessTokenExpiresAt: tokens.accessTokenExpiresAt)
    }

    /// Applies rotated tokens from `POST /v1/auth/refresh`.
    public func refreshed(with tokens: SessionTokens) -> AuthSession {
        var copy = self
        copy.accessToken = tokens.accessToken
        copy.refreshToken = tokens.refreshToken
        copy.accessTokenExpiresAt = tokens.accessTokenExpiresAt
        return copy
    }

    /// True when the access token expires within `leeway` (refresh proactively).
    public func isExpiring(within leeway: TimeInterval = 60, now: Date = .now) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(now) < leeway
    }
}

/// Where the session lives. Implementations must be thread-safe.
public protocol SessionStore: Sendable {
    func load() -> AuthSession?
    func save(_ session: AuthSession) throws
    func clear()
}

/// Process-memory store for previews, tests and the mock server.
public final class InMemorySessionStore: SessionStore {
    private let storage: Mutex<AuthSession?>

    public init(_ session: AuthSession? = nil) {
        storage = Mutex(session)
    }

    public func load() -> AuthSession? { storage.withLock { $0 } }
    public func save(_ session: AuthSession) throws { storage.withLock { $0 = session } }
    public func clear() { storage.withLock { $0 = nil } }
}
