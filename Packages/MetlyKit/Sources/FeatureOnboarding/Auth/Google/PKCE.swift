import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636), S256 method.
nonisolated enum PKCE {
    /// 32 random bytes → 43-character base64url verifier (RFC 7636 §4.1 allows 43…128).
    static func makeVerifier() -> String {
        randomURLSafeString(byteCount: 32)
    }

    /// `BASE64URL(SHA256(ASCII(code_verifier)))`.
    static func challenge(for verifier: String) -> String {
        base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    /// Unguessable token for `state` / `nonce`. `SystemRandomNumberGenerator` is cryptographically
    /// secure on Apple platforms.
    static func randomURLSafeString(byteCount: Int) -> String {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0..<byteCount).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        return base64URLEncoded(Data(bytes))
    }

    /// Base64 with the URL-safe alphabet and no padding.
    static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    /// Inverse of `base64URLEncoded`, restoring padding.
    static func base64URLDecoded(_ string: String) -> Data? {
        var base64 = string
            .replacing("-", with: "+")
            .replacing("_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}
