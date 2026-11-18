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
///
/// When the Telegram app is installed and the backend offers it, the sign-in runs in the Telegram app
/// instead: it reopens this app through a Universal Link (see `TelegramAppReturn`), so the user never
/// has to switch back by hand. Anything missing on that path falls back to the browser sheet.
struct TelegramSignInClient {
    /// Same shape as `GoogleSignInClient.WebAuthenticator`.
    typealias WebAuthenticator = @MainActor (_ url: URL, _ callbackScheme: String) async throws -> URL

    /// Builds the backend URL that starts the flow; nil when there is no backend (in-app mock server).
    var authorizationURL: @MainActor (_ codeChallenge: String, _ state: String, _ nonce: String) -> URL?
    /// The app's URL scheme the backend redirects to (must equal `APP_URL_SCHEME` on the server).
    var callbackScheme = Brand.urlScheme
    var authenticate: WebAuthenticator
    /// Whether the Telegram app is installed (`tg://` can be opened).
    var telegramAppInstalled: @MainActor () -> Bool = { false }
    /// The backend's `tg://` link for the Telegram-app flow; nil → browser flow.
    var appLink: @MainActor (_ codeChallenge: String, _ state: String, _ nonce: String) async -> URL? = { _, _, _ in nil }
    /// Opens the link in the Telegram app; false when it could not be opened.
    var openTelegram: @MainActor (_ url: URL) async -> Bool = { _ in false }
    /// Receives the Telegram app's link back into this app.
    var telegramReturn = TelegramAppReturn.shared

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

        let challenge = PKCE.challenge(for: verifier)
        if telegramAppInstalled(), let link = await appLink(challenge, state, nonce),
           let returnURL = try await telegramReturn.run(opening: link, with: openTelegram) {
            let code = try TelegramAuthorizationResponse.code(from: returnURL, expectedState: state, stateRequired: false)
            return TelegramSignInCredential(code: code, codeVerifier: verifier, nonce: nonce, flow: .app)
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
