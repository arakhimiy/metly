import AuthenticationServices
import Foundation
import MetlyCore

/// Google sign-in without any SDK: OAuth 2.0 authorization code + PKCE in an
/// `ASWebAuthenticationSession` (shared browser session, i.e. `prefersEphemeralWebBrowserSession == false`),
/// then a direct code exchange at `oauth2.googleapis.com/token`.
struct GoogleSignInClient {
    /// Opens the authorization URL and returns the redirect URL. In the app this is SwiftUI's
    /// `webAuthenticationSession.authenticate(using:callback:preferredBrowserSession:additionalHeaderFields:)`.
    typealias WebAuthenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    var configuration: GoogleOAuthConfiguration?
    var authenticate: WebAuthenticator
    var session: URLSession = .shared

    func signIn() async throws -> GoogleSignInCredential {
        guard let configuration else {
            #if DEBUG
            // No client ID in this build (simulator / local dev): continue with a labelled fake account
            // so the rest of onboarding can be exercised. Never compiled into Release.
            return .debugMock
            #else
            throw GoogleSignInError.notConfigured
            #endif
        }

        let verifier = PKCE.makeVerifier()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let nonce = PKCE.randomURLSafeString(byteCount: 16)
        let request = GoogleAuthorizationRequest(configuration: configuration,
                                                 codeChallenge: PKCE.challenge(for: verifier),
                                                 state: state, nonce: nonce)

        let callbackURL: URL
        do {
            callbackURL = try await authenticate(request.url, configuration.callbackScheme)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw GoogleSignInError.cancelled
        }

        let code = try GoogleAuthorizationResponse.code(from: callbackURL, expectedState: state)
        let tokens = try await GoogleTokenExchange(configuration: configuration, session: session)
            .exchange(code: code, verifier: verifier)

        guard let claims = IDTokenClaims.decode(jwt: tokens.idToken),
              claims.nonce == nonce,
              claims.audience.contains(configuration.clientID) else {
            throw GoogleSignInError.invalidIDToken
        }

        return GoogleSignInCredential(idToken: tokens.idToken, accessToken: tokens.accessToken,
                                      fullName: claims.displayName, email: claims.email)
    }
}

#if DEBUG
extension GoogleSignInCredential {
    /// Clearly fake credential used only when `MetlyGoogleClientID` is missing in a DEBUG build.
    static let debugMock = GoogleSignInCredential(
        idToken: "DEBUG-MOCK-GOOGLE-ID-TOKEN",
        accessToken: nil,
        fullName: "Debug Google User",
        email: "debug.google@example.com"
    )
}
#endif
