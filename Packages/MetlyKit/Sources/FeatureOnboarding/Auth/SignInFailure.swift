import Foundation

/// Alert content for a failed sign-in (cancellations never produce one).
struct SignInFailure: Equatable {
    var title: String = String(localized: "Couldn’t Sign In")
    var message: String

    static let appleDidNotFinish = SignInFailure(message: String(localized: "Sign in with Apple didn’t finish. Try again."))
    static let googleDidNotFinish = SignInFailure(message: String(localized: "Google sign-in didn’t finish. Try again."))

    static func from(_ error: any Error, provider: AuthProvider) -> SignInFailure {
        if let google = error as? GoogleSignInError {
            return SignInFailure(message: message(for: google))
        }
        if error is URLError {
            return SignInFailure(message: String(localized: "Check your connection and try again."))
        }
        // Swift errors from the auth service carry user-facing copy; bridged framework errors
        // (ASAuthorizationError, ASWebAuthenticationSessionError…) only have technical descriptions.
        if !(error is any CustomNSError),
           let described = (error as? any LocalizedError)?.errorDescription, !described.isEmpty {
            return SignInFailure(message: described)
        }
        return switch provider {
        case .apple: .appleDidNotFinish
        case .google: .googleDidNotFinish
        }
    }

    private static func message(for error: GoogleSignInError) -> String {
        switch error {
        case .notConfigured:
            String(localized: "Google sign-in isn’t available in this version. Continue with Apple instead.")
        case .stateMismatch, .missingCode, .invalidIDToken:
            String(localized: "Google sign-in didn’t finish securely. Try again.")
        case .providerError, .tokenExchangeFailed:
            String(localized: "Google couldn’t confirm your account. Try again.")
        case .cancelled:
            ""
        }
    }
}
