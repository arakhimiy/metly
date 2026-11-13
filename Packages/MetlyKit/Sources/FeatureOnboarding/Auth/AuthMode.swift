import AuthenticationServices
import MetlyCore
import SwiftUI

/// AUTH_SIGNUP is shown for new accounts and, from "Already have an account? Sign In", for returning ones.
/// Both run the same Apple / Google / Telegram flows; the backend decides whether setup is needed.
enum AuthMode: Hashable {
    case signUp, signIn

    var title: LocalizedStringKey {
        switch self {
        case .signUp: "Create your \(Brand.appName)"
        case .signIn: "Welcome Back"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .signUp: "It takes a minute. You can make your first card right after."
        case .signIn: "Sign in with the account you used before. Your cards and people sync automatically."
        }
    }

    /// Title of the custom Sign in with Apple button (HIG: "Continue with Apple" / "Sign In with Apple").
    var appleTitle: LocalizedStringKey {
        switch self {
        case .signUp: "Continue with Apple"
        case .signIn: "Sign In with Apple"
        }
    }

    var googleTitle: LocalizedStringKey {
        switch self {
        case .signUp: "Continue with Google"
        case .signIn: "Sign In with Google"
        }
    }

    var telegramTitle: LocalizedStringKey {
        switch self {
        case .signUp: "Continue with Telegram"
        case .signIn: "Sign In with Telegram"
        }
    }
}
