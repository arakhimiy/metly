import Foundation

nonisolated enum TelegramSignInError: Error, Equatable, Sendable {
    /// No backend to start the flow (a Release build always has one).
    case notConfigured
    /// User closed the sheet or declined on Telegram's consent page — handled silently.
    case cancelled
    /// Callback `state` didn't match the one we sent (possible CSRF).
    case stateMismatch
    case missingCode
    /// `error=` returned on the redirect (other than `access_denied`).
    case providerError(String)
}
