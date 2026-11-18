import Foundation

/// The app's half of Log In with Telegram (OpenID Connect + PKCE): the authorization code Telegram
/// sent back through the backend's callback, plus the PKCE verifier and nonce only this app knows.
/// The backend redeems the code with its client secret and verifies the signed id_token.
public struct TelegramSignInCredential: Sendable, Hashable {
    /// Where Telegram sent the code: the backend's callback (browser sheet) or the app's Universal Link
    /// (Telegram app). The backend must redeem it against the same redirect URI.
    public enum Flow: String, Sendable, Hashable {
        case web
        case app
    }

    public var code: String
    public var codeVerifier: String
    public var nonce: String
    public var flow: Flow

    public init(code: String, codeVerifier: String, nonce: String, flow: Flow = .web) {
        self.code = code
        self.codeVerifier = codeVerifier
        self.nonce = nonce
        self.flow = flow
    }
}
