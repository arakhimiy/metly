import Foundation

nonisolated enum GoogleSignInError: Error, Equatable, Sendable {
    /// No usable `MetlyGoogleClientID` in a Release build.
    case notConfigured
    /// User closed the sheet or declined consent — handled silently.
    case cancelled
    /// Callback `state` didn't match the one we sent (possible CSRF).
    case stateMismatch
    case missingCode
    /// `error=` returned by Google on the redirect (other than `access_denied`).
    case providerError(String)
    /// Token endpoint returned a non-2xx response.
    case tokenExchangeFailed(String?)
    /// id_token missing, malformed, wrong audience or nonce.
    case invalidIDToken
}
