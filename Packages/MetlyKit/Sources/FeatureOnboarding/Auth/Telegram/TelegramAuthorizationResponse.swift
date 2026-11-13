import Foundation

/// Parses the backend's hand-back into the app (`<scheme>://auth/telegram?code=…&state=…`, or
/// `?error=…&state=…` when the user declined on Telegram's consent page).
nonisolated enum TelegramAuthorizationResponse {
    static func code(from callbackURL: URL, expectedState: String) throws(TelegramSignInError) -> String {
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
        guard value("state") == expectedState else { throw .stateMismatch }
        guard let code = value("code"), !code.isEmpty else { throw .missingCode }
        return code
    }
}
