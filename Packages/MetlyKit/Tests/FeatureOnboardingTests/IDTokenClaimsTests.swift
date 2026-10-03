import Foundation
import Testing
@testable import FeatureOnboarding

@Suite("id_token claims")
struct IDTokenClaimsTests {
    /// Builds an unsigned compact JWS around `payload`.
    static func jwt(_ payload: String) -> String {
        let header = PKCE.base64URLEncoded(Data(#"{"alg":"RS256","kid":"test","typ":"JWT"}"#.utf8))
        let body = PKCE.base64URLEncoded(Data(payload.utf8))
        return "\(header).\(body).c2lnbmF0dXJl"
    }

    @Test func decodesGoogleClaims() throws {
        let token = Self.jwt("""
        {"iss":"https://accounts.google.com","aud":"123.apps.googleusercontent.com","sub":"10769150350006150715",
         "email":"aziza@tezkor.uz","email_verified":true,"name":"Aziza Karimova","given_name":"Aziza",
         "family_name":"Karimova","nonce":"n-0S6_WzA2Mj","exp":1790000000}
        """)
        let claims = try #require(IDTokenClaims.decode(jwt: token))
        #expect(claims.subject == "10769150350006150715")
        #expect(claims.email == "aziza@tezkor.uz")
        #expect(claims.emailVerified == true)
        #expect(claims.displayName == "Aziza Karimova")
        #expect(claims.nonce == "n-0S6_WzA2Mj")
        #expect(claims.audience == ["123.apps.googleusercontent.com"])
        #expect(claims.issuer == "https://accounts.google.com")
        #expect(claims.expiresAt == Date(timeIntervalSince1970: 1_790_000_000))
    }

    @Test func decodesAppleStyleClaims() throws {
        // Apple: string "true", private relay email, no name, aud as array is also accepted.
        let token = Self.jwt(#"{"iss":"https://appleid.apple.com","aud":["com.metly.app"],"sub":"001234.abcd","email":"x7y2@privaterelay.appleid.com","email_verified":"true"}"#)
        let claims = try #require(IDTokenClaims.decode(jwt: token))
        #expect(claims.email == "x7y2@privaterelay.appleid.com")
        #expect(claims.emailVerified == true)
        #expect(claims.audience == ["com.metly.app"])
        #expect(claims.displayName == nil)
    }

    @Test func fallsBackToGivenAndFamilyName() throws {
        let token = Self.jwt(#"{"sub":"1","aud":"a","given_name":"Jasur","family_name":"Toshmatov"}"#)
        let claims = try #require(IDTokenClaims.decode(jwt: token))
        #expect(claims.displayName?.contains("Jasur") == true)
        #expect(claims.displayName?.contains("Toshmatov") == true)
    }

    @Test func decodesPayloadsThatNeedPadding() throws {
        // Lengths chosen so the base64url payload is not a multiple of 4.
        for name in ["A", "Ab", "Abc", "Abcd"] {
            let token = Self.jwt(#"{"sub":"1","aud":"a","name":"\#(name)"}"#)
            #expect(IDTokenClaims.decode(jwt: token)?.name == name)
        }
    }

    @Test func handlesUnicodeNames() throws {
        let token = Self.jwt(#"{"sub":"1","aud":"a","name":"Ўткир Каримов"}"#)
        #expect(IDTokenClaims.decode(jwt: token)?.displayName == "Ўткир Каримов")
    }

    @Test(arguments: ["", "abc", "a.b", "a.b.c.d", "a.!!!.c", Self.jwt(#"{"aud":"missing-sub"}"#)])
    func rejectsMalformedTokens(_ token: String) {
        #expect(IDTokenClaims.decode(jwt: token) == nil)
    }

    @Test func readsEmailFromAppleIdentityToken() {
        let token = Data(Self.jwt(#"{"sub":"1","aud":"com.metly.app","email":"aziza@icloud.com"}"#).utf8)
        #expect(AppleCredentialMapper.email(fromIdentityToken: token) == "aziza@icloud.com")
        #expect(AppleCredentialMapper.email(fromIdentityToken: nil) == nil)
    }

    @Test func ignoresEmptyAppleName() {
        #expect(AppleCredentialMapper.nonEmpty(PersonNameComponents()) == nil)
        #expect(AppleCredentialMapper.displayName(PersonNameComponents(givenName: " ", familyName: "")) == nil)
        let name = PersonNameComponents(givenName: "Aziza", familyName: "Karimova")
        #expect(AppleCredentialMapper.displayName(name)?.contains("Aziza") == true)
    }
}
