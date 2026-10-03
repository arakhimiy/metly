import Foundation

/// Google "iOS" OAuth client (no client secret; PKCE protects the code exchange).
/// The client ID comes from the `MetlyGoogleClientID` Info.plist key (`$(GOOGLE_CLIENT_ID)` build setting).
nonisolated struct GoogleOAuthConfiguration: Equatable, Sendable {
    static let infoPlistKey = "MetlyGoogleClientID"
    static let clientIDSuffix = ".apps.googleusercontent.com"
    static let reversedPrefix = "com.googleusercontent.apps."

    /// e.g. `1234-abcd.apps.googleusercontent.com`
    let clientID: String

    /// Returns nil when the value is missing, empty, an unresolved `$(…)` build variable,
    /// or not a Google client ID.
    init?(clientID raw: String?) {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              !value.contains("$("),
              value.hasSuffix(Self.clientIDSuffix),
              value.count > Self.clientIDSuffix.count,
              !value.contains(where: \.isWhitespace) else { return nil }
        clientID = value
    }

    static func fromBundle(_ bundle: Bundle = .main) -> GoogleOAuthConfiguration? {
        GoogleOAuthConfiguration(clientID: bundle.object(forInfoDictionaryKey: infoPlistKey) as? String)
    }

    /// `com.googleusercontent.apps.1234-abcd` — the custom URL scheme Google redirects to.
    var reversedClientID: String {
        Self.reversedPrefix + clientID.dropLast(Self.clientIDSuffix.count)
    }

    /// Scheme `ASWebAuthenticationSession` listens for.
    var callbackScheme: String { reversedClientID }

    /// `com.googleusercontent.apps.1234-abcd:/oauthredirect`
    var redirectURI: String { "\(reversedClientID):/oauthredirect" }
}
