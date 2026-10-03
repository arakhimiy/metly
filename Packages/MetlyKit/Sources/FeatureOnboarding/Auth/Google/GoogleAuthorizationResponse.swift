import Foundation

/// Parses Google's redirect (`com.googleusercontent.apps.…:/oauthredirect?code=…&state=…`).
nonisolated enum GoogleAuthorizationResponse {
    static func code(from callbackURL: URL, expectedState: String) throws(GoogleSignInError) -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            throw error == "access_denied" ? .cancelled : .providerError(error)
        }
        guard value("state") == expectedState else { throw .stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }
}
