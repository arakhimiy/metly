import Foundation

/// The app's half of Log In with Telegram (OpenID Connect + PKCE): the authorization code Telegram
/// sent back through the backend's callback, plus the PKCE verifier and nonce only this app knows.
/// The backend redeems the code with its client secret and verifies the signed id_token.
public struct TelegramSignInCredential: Sendable, Hashable {
    public var code: String
    public var codeVerifier: String
    public var nonce: String

    public init(code: String, codeVerifier: String, nonce: String) {
        self.code = code
        self.codeVerifier = codeVerifier
        self.nonce = nonce
    }
}
