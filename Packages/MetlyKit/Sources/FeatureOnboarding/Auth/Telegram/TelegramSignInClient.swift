import AuthenticationServices
import Foundation
import MetlyCore

/// Log In with Telegram (https://core.telegram.org/bots/telegram-login), no SDK: OpenID Connect
/// authorization code + PKCE in an `ASWebAuthenticationSession`.
///
/// The session opens the backend's `/v1/auth/telegram/authorize`, which redirects to Telegram with the
/// bot's client id; Telegram returns to the backend's registered callback, which hands `code` + `state`
/// back through the app's URL scheme. The app checks `state` and gives the code, its PKCE verifier and
/// nonce to the backend, which alone holds the client secret and verifies the id_token.
struct TelegramSignInClient {
    /// Same shape as `GoogleSignInClient.WebAuthenticator`.
    typealias WebAuthenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    /// Builds the backend URL that starts the flow; nil when there is no backend (in-app mock server).
    var authorizationURL: @MainActor (_ codeChallenge: String, _ state: String, _ nonce: String) -> URL?
    /// The app's URL scheme the backend redirects to (must equal `APP_URL_SCHEME` on the server).
    var callbackScheme = Brand.urlScheme
    var authenticate: WebAuthenticator

    func signIn() async throws -> TelegramSignInCredential {
        let verifier = PKCE.makeVerifier()
        let state = PKCE.randomURLSafeString(byteCount: 16)
        let nonce = PKCE.randomURLSafeString(byteCount: 16)

        guard let url = authorizationURL(PKCE.challenge(for: verifier), state, nonce) else {
            #if DEBUG
            // In-app mock server (no backend): the mock accepts this credential, so onboarding can be
            // exercised in the simulator. Never compiled into Release.
            return TelegramSignInCredential(code: "DEBUG-MOCK-TELEGRAM-CODE", codeVerifier: verifier, nonce: nonce)
            #else
            throw TelegramSignInError.notConfigured
            #endif
        }

        let callbackURL: URL
        do {
            callbackURL = try await authenticate(url, callbackScheme)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            throw TelegramSignInError.cancelled
        }
        let code = try TelegramAuthorizationResponse.code(from: callbackURL, expectedState: state)
        return TelegramSignInCredential(code: code, codeVerifier: verifier, nonce: nonce)
    }

}
