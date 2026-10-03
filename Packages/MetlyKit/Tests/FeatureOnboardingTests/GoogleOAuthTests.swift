import Foundation
import Testing
@testable import FeatureOnboarding

@Suite("Google OAuth")
struct GoogleOAuthTests {
    static let clientID = "1234567890-abcdefg.apps.googleusercontent.com"

    var configuration: GoogleOAuthConfiguration {
        get throws { try #require(GoogleOAuthConfiguration(clientID: Self.clientID)) }
    }

    // MARK: Configuration

    @Test func derivesReversedClientIDAndRedirect() throws {
        let configuration = try configuration
        #expect(configuration.reversedClientID == "com.googleusercontent.apps.1234567890-abcdefg")
        #expect(configuration.callbackScheme == "com.googleusercontent.apps.1234567890-abcdefg")
        #expect(configuration.redirectURI == "com.googleusercontent.apps.1234567890-abcdefg:/oauthredirect")
    }

    @Test(arguments: [nil, "", "   ", "$(GOOGLE_CLIENT_ID)", "not-a-client-id", ".apps.googleusercontent.com", "12 34.apps.googleusercontent.com"])
    func rejectsMissingOrUnresolvedClientID(_ raw: String?) {
        #expect(GoogleOAuthConfiguration(clientID: raw) == nil)
    }

    @Test func trimsWhitespaceAroundClientID() {
        #expect(GoogleOAuthConfiguration(clientID: "  \(Self.clientID)\n")?.clientID == Self.clientID)
    }

    // MARK: Authorization URL

    @Test func buildsAuthorizationURL() throws {
        let request = GoogleAuthorizationRequest(configuration: try configuration, codeChallenge: "CHALLENGE",
                                                 state: "STATE", nonce: "NONCE")
        let components = try #require(URLComponents(url: request.url, resolvingAgainstBaseURL: false))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.scheme == "https")
        #expect(components.host == "accounts.google.com")
        #expect(components.path == "/o/oauth2/v2/auth")
        #expect(query["client_id"] == Self.clientID)
        #expect(query["redirect_uri"] == "com.googleusercontent.apps.1234567890-abcdefg:/oauthredirect")
        #expect(query["response_type"] == "code")
        #expect(query["scope"] == "openid email profile")
        #expect(query["code_challenge"] == "CHALLENGE")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "STATE")
        #expect(query["nonce"] == "NONCE")
        #expect(query["prompt"] == "select_account")
        #expect(request.url.absoluteString.contains("scope=openid%20email%20profile"))
    }

    // MARK: Redirect parsing

    @Test func extractsCodeWhenStateMatches() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.1234567890-abcdefg:/oauthredirect?state=S1&code=4%2F0Ab_xyz&scope=email"))
        #expect(try GoogleAuthorizationResponse.code(from: url, expectedState: "S1") == "4/0Ab_xyz")
    }

    @Test func rejectsStateMismatch() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.x:/oauthredirect?state=OTHER&code=abc"))
        #expect(throws: GoogleSignInError.stateMismatch) {
            try GoogleAuthorizationResponse.code(from: url, expectedState: "S1")
        }
    }

    @Test func treatsAccessDeniedAsCancellation() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.x:/oauthredirect?error=access_denied&state=S1"))
        #expect(throws: GoogleSignInError.cancelled) {
            try GoogleAuthorizationResponse.code(from: url, expectedState: "S1")
        }
    }

    @Test func surfacesProviderErrors() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.x:/oauthredirect?error=invalid_request&state=S1"))
        #expect(throws: GoogleSignInError.providerError("invalid_request")) {
            try GoogleAuthorizationResponse.code(from: url, expectedState: "S1")
        }
    }

    @Test func requiresCode() throws {
        let url = try #require(URL(string: "com.googleusercontent.apps.x:/oauthredirect?state=S1"))
        #expect(throws: GoogleSignInError.missingCode) {
            try GoogleAuthorizationResponse.code(from: url, expectedState: "S1")
        }
    }

    // MARK: Token request

    @Test func buildsTokenExchangeRequest() throws {
        let request = GoogleTokenExchange.request(code: "4/0Ab_xyz", verifier: "VERIFIER-123", configuration: try configuration)
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        let pairs = Set(body.split(separator: "&").map(String.init))

        #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
        #expect(pairs.contains("grant_type=authorization_code"))
        #expect(pairs.contains("code=4%2F0Ab_xyz"))
        #expect(pairs.contains("code_verifier=VERIFIER-123"))
        #expect(pairs.contains("client_id=1234567890-abcdefg.apps.googleusercontent.com"))
        #expect(pairs.contains("redirect_uri=com.googleusercontent.apps.1234567890-abcdefg%3A%2Foauthredirect"))
        #expect(!body.contains("client_secret"))
    }

    @Test func decodesTokenResponse() throws {
        let json = Data(#"{"access_token":"ya29.a0","expires_in":3599,"scope":"openid","token_type":"Bearer","id_token":"h.p.s"}"#.utf8)
        let response = try JSONDecoder().decode(GoogleTokenResponse.self, from: json)
        #expect(response == GoogleTokenResponse(idToken: "h.p.s", accessToken: "ya29.a0"))
    }
}
