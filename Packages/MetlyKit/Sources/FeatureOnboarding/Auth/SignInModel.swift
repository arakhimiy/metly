import AuthenticationServices
import MetlyCore
import Observation

/// Drives AUTH_SIGNUP: one sign-in at a time, loading state, error alert, silent cancellation.
@Observable
final class SignInModel {
    private(set) var inFlight: AuthProvider?
    private(set) var failure: SignInFailure?
    var isShowingFailure = false

    var isWorking: Bool { inFlight != nil }

    init(inFlight: AuthProvider? = nil, failure: SignInFailure? = nil) {
        self.inFlight = inFlight
        self.failure = failure
        isShowingFailure = failure != nil
    }

    // MARK: Apple

    func configure(_ request: ASAuthorizationAppleIDRequest) {
        request.requestedScopes = [.fullName, .email]
    }

    func completeApple(_ result: Result<ASAuthorization, any Error>, auth: any AuthServicing) async -> SignInOutcome? {
        let authorization: ASAuthorization
        switch result {
        case .success(let value):
            authorization = value
        case .failure(let error):
            if !AppleCredentialMapper.isCancellation(error) {
                present(SignInFailure.from(error, provider: .apple))
            }
            return nil
        }
        guard let apple = authorization.credential as? ASAuthorizationAppleIDCredential else {
            present(.appleDidNotFinish)
            return nil
        }
        let credential = AppleCredentialMapper.credential(from: apple)

        return await perform(.apple) {
            let result = try await auth.signIn(apple: credential)
            return SignInOutcome(
                result: result,
                provider: .apple,
                suggestedName: result.suggestedName ?? AppleCredentialMapper.displayName(credential.fullName),
                email: result.email ?? credential.email ?? AppleCredentialMapper.email(fromIdentityToken: credential.identityToken)
            )
        }
    }

    // MARK: Google

    func signInWithGoogle(client: GoogleSignInClient, auth: any AuthServicing) async -> SignInOutcome? {
        await perform(.google) {
            let credential = try await client.signIn()
            let result = try await auth.signIn(google: credential)
            return SignInOutcome(result: result, provider: .google,
                                 suggestedName: result.suggestedName ?? credential.fullName,
                                 email: result.email ?? credential.email)
        }
    }

    // MARK: Private

    private func perform(_ provider: AuthProvider, _ work: () async throws -> SignInOutcome) async -> SignInOutcome? {
        guard inFlight == nil else { return nil }
        inFlight = provider
        defer { inFlight = nil }
        do {
            return try await work()
        } catch GoogleSignInError.cancelled {
            return nil
        } catch {
            present(SignInFailure.from(error, provider: provider))
            return nil
        }
    }

    private func present(_ failure: SignInFailure) {
        self.failure = failure
        isShowingFailure = true
    }
}
