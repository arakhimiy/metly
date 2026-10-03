import AuthenticationServices
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// AUTH_SIGNUP — "Create your Metly" (or "Welcome Back" in sign-in mode).
struct AuthView: View {
    let mode: AuthMode

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.webAuthenticationSession) private var webAuthenticationSession
    @State private var model: SignInModel

    init(mode: AuthMode, model: SignInModel = SignInModel()) {
        self.mode = mode
        _model = State(initialValue: model)
    }

    var body: some View {
        FillOrScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 16)
                AuthHeader(mode: mode)
                Spacer(minLength: 16)
                VStack(spacing: 20) {
                    AuthProviderButtons(mode: mode,
                                        onAppleRequest: model.configure,
                                        onAppleCompletion: completeApple,
                                        onGoogle: signInWithGoogle)
                    if mode == .signUp {
                        SignInPrompt()
                    }
                    LegalFooter()
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 12)
        }
        .disabled(model.isWorking)
        .overlay {
            if model.isWorking {
                SigningInOverlay()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(model.isWorking)
        .alert(model.failure?.title ?? "", isPresented: $model.isShowingFailure, presenting: model.failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private func completeApple(_ result: Result<ASAuthorization, any Error>) {
        Task {
            if let outcome = await model.completeApple(result, auth: services.auth) {
                finish(outcome)
            }
        }
    }

    private func signInWithGoogle() {
        let session = webAuthenticationSession
        let client = GoogleSignInClient(configuration: .fromBundle()) { url, scheme in
            try await session.authenticate(using: url, callback: .customScheme(scheme),
                                           preferredBrowserSession: .shared, additionalHeaderFields: [:])
        }
        Task {
            if let outcome = await model.signInWithGoogle(client: client, auth: services.auth) {
                finish(outcome)
            }
        }
    }

    private func finish(_ outcome: SignInOutcome) {
        OnboardingCoordinator.didSignIn(outcome, router: router, services: services, store: OnboardingStore())
    }
}

#Preview("Sign up") {
    NavigationStack { AuthView(mode: .signUp) }
        .metlyPreview(.signedOut)
}

#Preview("Sign up · dark") {
    NavigationStack { AuthView(mode: .signUp) }
        .metlyPreview(.signedOut)
        .preferredColorScheme(.dark)
}

#Preview("Sign in") {
    NavigationStack { AuthView(mode: .signIn) }
        .metlyPreview(.signedOut)
}

#Preview("Sign up · loading") {
    NavigationStack { AuthView(mode: .signUp, model: SignInModel(inFlight: .google)) }
        .metlyPreview(.signedOut)
}

#Preview("Sign up · error") {
    NavigationStack {
        AuthView(mode: .signUp,
                 model: SignInModel(failure: SignInFailure(message: "Check your connection and try again.")))
    }
    .metlyPreview(.signedOut)
}

#Preview("Sign up · accessibility size") {
    NavigationStack { AuthView(mode: .signUp) }
        .metlyPreview(.signedOut)
        .dynamicTypeSize(.accessibility3)
}
