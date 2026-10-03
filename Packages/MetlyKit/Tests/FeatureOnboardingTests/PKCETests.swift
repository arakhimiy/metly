import Foundation
import Testing
@testable import FeatureOnboarding

@Suite("PKCE")
struct PKCETests {
    /// RFC 7636 Appendix B test vector.
    @Test func challengeMatchesRFC7636Vector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(PKCE.challenge(for: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsURLSafeAndWithinRFCLength() {
        let verifier = PKCE.makeVerifier()
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        #expect((43...128).contains(verifier.count))
        #expect(verifier.allSatisfy(allowed.contains))
    }

    @Test func verifiersAreUnique() {
        let verifiers = Set((0..<50).map { _ in PKCE.makeVerifier() })
        #expect(verifiers.count == 50)
    }

    @Test func challengeIsUnpaddedBase64URL() {
        let challenge = PKCE.challenge(for: PKCE.makeVerifier())
        #expect(challenge.count == 43)
        #expect(!challenge.contains("="))
        #expect(!challenge.contains("+"))
        #expect(!challenge.contains("/"))
    }

    @Test(arguments: ["", "f", "fo", "foo", "foob", "fooba", "foobar", "√ünicode ✓"])
    func base64URLRoundTrips(_ text: String) {
        let encoded = PKCE.base64URLEncoded(Data(text.utf8))
        #expect(!encoded.contains("="))
        #expect(PKCE.base64URLDecoded(encoded) == Data(text.utf8))
    }
}
