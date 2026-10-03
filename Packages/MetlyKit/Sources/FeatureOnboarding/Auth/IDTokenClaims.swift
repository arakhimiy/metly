import Foundation

/// The OpenID Connect claims we read from a Google or Apple id_token, for prefill only.
/// The signature is NOT verified here — the backend validates the token; the app never trusts
/// these values for authorization.
nonisolated struct IDTokenClaims: Decodable, Equatable, Sendable {
    var subject: String
    var email: String?
    var emailVerified: Bool?
    var name: String?
    var givenName: String?
    var familyName: String?
    var nonce: String?
    /// `aud` may be a single string or an array.
    var audience: [String]
    var issuer: String?
    var expiresAt: Date?

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case email
        case emailVerified = "email_verified"
        case name
        case givenName = "given_name"
        case familyName = "family_name"
        case nonce
        case audience = "aud"
        case issuer = "iss"
        case expiresAt = "exp"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subject = try container.decode(String.self, forKey: .subject)
        email = try container.decodeIfPresent(String.self, forKey: .email)
        // Google sends a JSON bool, Apple sends the string "true".
        if let flag = try? container.decodeIfPresent(Bool.self, forKey: .emailVerified) {
            emailVerified = flag
        } else if let text = try? container.decodeIfPresent(String.self, forKey: .emailVerified) {
            emailVerified = text.lowercased() == "true"
        }
        name = try container.decodeIfPresent(String.self, forKey: .name)
        givenName = try container.decodeIfPresent(String.self, forKey: .givenName)
        familyName = try container.decodeIfPresent(String.self, forKey: .familyName)
        nonce = try container.decodeIfPresent(String.self, forKey: .nonce)
        if let single = try? container.decode(String.self, forKey: .audience) {
            audience = [single]
        } else {
            audience = (try? container.decode([String].self, forKey: .audience)) ?? []
        }
        issuer = try container.decodeIfPresent(String.self, forKey: .issuer)
        expiresAt = try container.decodeIfPresent(Double.self, forKey: .expiresAt).map(Date.init(timeIntervalSince1970:))
    }

    /// Full name for SETUP_PROFILE, falling back to given + family name.
    var displayName: String? {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        var components = PersonNameComponents()
        components.givenName = givenName
        components.familyName = familyName
        guard givenName != nil || familyName != nil else { return nil }
        let formatted = components.formatted()
        return formatted.isEmpty ? nil : formatted
    }

    /// Decodes the payload segment of a compact JWS (`header.payload.signature`).
    static func decode(jwt: String) -> IDTokenClaims? {
        let segments = jwt.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count == 3, let payload = PKCE.base64URLDecoded(String(segments[1])) else { return nil }
        return try? JSONDecoder().decode(IDTokenClaims.self, from: payload)
    }
}
