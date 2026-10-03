import Foundation

/// Builds the Google authorization-code URL (OpenID Connect, PKCE S256).
nonisolated struct GoogleAuthorizationRequest: Sendable {
    static let endpoint = URL(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    static let scopes = ["openid", "email", "profile"]

    var configuration: GoogleOAuthConfiguration
    var codeChallenge: String
    var state: String
    var nonce: String

    var queryItems: [URLQueryItem] {
        [
            URLQueryItem(name: "client_id", value: configuration.clientID),
            URLQueryItem(name: "redirect_uri", value: configuration.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "nonce", value: nonce),
            // The shared browser session may already hold a Google cookie — let people pick the account.
            URLQueryItem(name: "prompt", value: "select_account"),
        ]
    }

    var url: URL {
        var components = URLComponents(url: Self.endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        return components?.url ?? Self.endpoint
    }
}
