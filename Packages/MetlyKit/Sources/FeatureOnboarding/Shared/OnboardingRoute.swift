/// Feature-internal pushes inside the onboarding NavigationStacks.
enum OnboardingRoute: Hashable {
    /// AUTH_SIGNUP — "Create your Metly".
    case signUp
    /// AUTH_SIGNUP in sign-in mode ("Already have an account? Sign In").
    case signIn

    var authMode: AuthMode {
        switch self {
        case .signUp: .signUp
        case .signIn: .signIn
        }
    }
}

/// Feature-internal pushes inside the setup NavigationStack.
enum SetupRoute: Hashable {
    /// SETUP_PERMISSIONS — "Allow Access".
    case permissions
}
