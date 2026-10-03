import SwiftUI

/// "Already have an account? Sign In" — pushes AUTH_SIGNUP in sign-in mode.
struct SignInPrompt: View {
    var body: some View {
        ViewThatFits {
            HStack(spacing: 4) { content }
            VStack(spacing: 4) { content }
        }
        .font(.subheadline)
    }

    @ViewBuilder
    private var content: some View {
        Text("Already have an account?")
            .foregroundStyle(.secondary)
        NavigationLink(value: OnboardingRoute.signIn) {
            Text("Sign In")
                .fontWeight(.semibold)
                .frame(minHeight: 44)
                .contentShape(.rect)
        }
    }
}
