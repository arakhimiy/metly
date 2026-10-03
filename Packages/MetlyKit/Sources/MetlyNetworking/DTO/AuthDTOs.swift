import Foundation
import MetlyCore

// Wire types for /v1/auth/* and /v1/me (account). Field docs live in docs/api/openapi.yaml.

public enum AuthProvider: String, Codable, Sendable, CaseIterable { case apple, google }

public struct PersonNameDTO: Codable, Sendable, Hashable {
    public var givenName: String?
    public var familyName: String?

    public init(givenName: String?, familyName: String?) {
        self.givenName = givenName
        self.familyName = familyName
    }

    public var formatted: String? {
        let name = [givenName, familyName].compactMap { $0?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " ")
        return name.isEmpty ? nil : name
    }
}

/// `POST /v1/auth/apple`. Apple sends name/email only on the very first authorization — forward them.
public struct AppleSignInRequest: Codable, Sendable, Hashable {
    public var identityToken: String
    public var authorizationCode: String?
    public var userIdentifier: String
    public var fullName: PersonNameDTO?
    public var email: String?
    /// Raw nonce whose SHA-256 was set on the ASAuthorizationAppleIDRequest (optional in v1).
    public var nonce: String?

    public init(identityToken: String, authorizationCode: String?, userIdentifier: String,
                fullName: PersonNameDTO?, email: String?, nonce: String? = nil) {
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.userIdentifier = userIdentifier
        self.fullName = fullName
        self.email = email
        self.nonce = nonce
    }
}

/// `POST /v1/auth/google` — the OpenID Connect `id_token` from the PKCE flow.
public struct GoogleSignInRequest: Codable, Sendable, Hashable {
    public var idToken: String
    public var nonce: String?

    public init(idToken: String, nonce: String? = nil) {
        self.idToken = idToken
        self.nonce = nonce
    }
}

public struct RefreshRequest: Codable, Sendable, Hashable {
    public var refreshToken: String
    public init(refreshToken: String) { self.refreshToken = refreshToken }
}

public struct LogoutRequest: Codable, Sendable, Hashable {
    public var refreshToken: String?
    public var allDevices: Bool
    public init(refreshToken: String?, allDevices: Bool = false) {
        self.refreshToken = refreshToken
        self.allDevices = allDevices
    }
}

public struct SessionTokens: Codable, Sendable, Hashable {
    public var accessToken: String
    public var refreshToken: String
    public var tokenType: String
    public var accessTokenExpiresAt: Date
    public var refreshTokenExpiresAt: Date?

    public init(accessToken: String, refreshToken: String, tokenType: String = "Bearer",
                accessTokenExpiresAt: Date, refreshTokenExpiresAt: Date? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenType = tokenType
        self.accessTokenExpiresAt = accessTokenExpiresAt
        self.refreshTokenExpiresAt = refreshTokenExpiresAt
    }
}

public struct UserDTO: Codable, Sendable, Hashable {
    public var id: UUID
    public var email: String?
    public var authProviders: [AuthProvider]
    public var createdAt: Date
    /// False until SETUP_PROFILE was completed on any device.
    public var profileComplete: Bool

    public init(id: UUID, email: String?, authProviders: [AuthProvider], createdAt: Date, profileComplete: Bool) {
        self.id = id
        self.email = email
        self.authProviders = authProviders
        self.createdAt = createdAt
        self.profileComplete = profileComplete
    }
}

public struct AuthResponse: Codable, Sendable, Hashable {
    public var session: SessionTokens
    public var user: UserDTO
    public var isNewUser: Bool
    /// Name prefill for SETUP_PROFILE (from Apple/Google), nil when unknown.
    public var suggestedName: String?

    public init(session: SessionTokens, user: UserDTO, isNewUser: Bool, suggestedName: String?) {
        self.session = session
        self.user = user
        self.isNewUser = isNewUser
        self.suggestedName = suggestedName
    }
}

/// `GET /v1/me`.
public struct MeResponse: Codable, Sendable, Hashable {
    public var user: UserDTO
    public var profile: ProfileDTO?
    public var entitlement: EntitlementDTO

    public init(user: UserDTO, profile: ProfileDTO?, entitlement: EntitlementDTO) {
        self.user = user
        self.profile = profile
        self.entitlement = entitlement
    }
}

/// `POST /v1/me/export` → 202.
public struct DataExportResponse: Codable, Sendable, Hashable {
    public var status: String
    public var requestedAt: Date
    /// Where the download link will be emailed.
    public var email: String?

    public init(status: String = "queued", requestedAt: Date, email: String?) {
        self.status = status
        self.requestedAt = requestedAt
        self.email = email
    }
}

/// Generic cursor page: `{ "items": [...], "nextCursor": "…" | null }`.
public struct Page<Item: Codable & Sendable & Hashable>: Codable, Sendable, Hashable {
    public var items: [Item]
    public var nextCursor: String?

    public init(items: [Item], nextCursor: String?) {
        self.items = items
        self.nextCursor = nextCursor
    }
}
