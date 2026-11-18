import Foundation

/// Parses the backend's hand-back into the app (`<scheme>://auth/telegram?code=…&state=…`, or
/// `?error=…&state=…` when the user declined on Telegram's consent page).
nonisolated enum TelegramAuthorizationResponse {
    /// `stateRequired: false` is for the Telegram app's Universal Link, which may not echo `state`; a
    /// state that is present must still match, and the code stays bound to this attempt's PKCE verifier.
    static func code(from callbackURL: URL, expectedState: String, stateRequired: Bool = true) throws(TelegramSignInError) -> String {
        let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        if let error = value("error") {
            switch error {
            case "access_denied": throw .cancelled
            case "temporarily_unavailable": throw .notConfigured   // the server has no Telegram login set up
            default: throw .providerError(error)
            }
        }
        switch value("state") {
        case expectedState?: break
        case nil where !stateRequired: break
        default: throw .stateMismatch
        }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }
}
