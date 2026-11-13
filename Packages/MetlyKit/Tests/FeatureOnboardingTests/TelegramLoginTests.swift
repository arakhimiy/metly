import Foundation
import MetlyCore
import Testing
@testable import FeatureOnboarding

@Suite("Log In with Telegram")
@MainActor
struct TelegramLoginTests {
    // MARK: Callback parsing

    @Test func readsCodeWhenStateMatches() throws {
        let url = try #require(URL(string: "tanishly://auth/telegram?code=abc123&state=S1"))
        #expect(try TelegramAuthorizationResponse.code(from: url, expectedState: "S1") == "abc123")
    }

    @Test func rejectsForeignStateAndMissingCode() throws {
        let forged = try #require(URL(string: "tanishly://auth/telegram?code=abc&state=OTHER"))
        #expect(throws: TelegramSignInError.stateMismatch) { try TelegramAuthorizationResponse.code(from: forged, expectedState: "S1") }
        let empty = try #require(URL(string: "tanishly://auth/telegram?state=S1"))
        #expect(throws: TelegramSignInError.missingCode) { try TelegramAuthorizationResponse.code(from: empty, expectedState: "S1") }
    }

    @Test func declinedConsentIsACancellationOtherErrorsAreNot() throws {
        let declined = try #require(URL(string: "tanishly://auth/telegram?error=access_denied&state=S1"))
        #expect(throws: TelegramSignInError.cancelled) { try TelegramAuthorizationResponse.code(from: declined, expectedState: "S1") }
        let unavailable = try #require(URL(string: "tanishly://auth/telegram?error=temporarily_unavailable&state=S1"))
        #expect(throws: TelegramSignInError.notConfigured) { try TelegramAuthorizationResponse.code(from: unavailable, expectedState: "S1") }
        let broken = try #require(URL(string: "tanishly://auth/telegram?error=invalid_request"))
        #expect(throws: TelegramSignInError.providerError("invalid_request")) {
            try TelegramAuthorizationResponse.code(from: broken, expectedState: "S1")
        }
    }

    // MARK: Client flow

    @Test func sendsPKCEToTheBackendAndReturnsCodeVerifierAndNonce() async throws {
        var seen: (challenge: String, state: String, nonce: String)?
        var openedScheme: String?
        let client = TelegramSignInClient(authorizationURL: { challenge, state, nonce in
            seen = (challenge, state, nonce)
            return URL(string: "https://api.example.test/v1/auth/telegram/authorize")
        }) { _, scheme in
            openedScheme = scheme
            return URL(string: "tanishly://auth/telegram?code=CODE&state=\(seen?.state ?? "")")!
        }

        let credential = try await client.signIn()
        let sent = try #require(seen)
        #expect(credential.code == "CODE")
        #expect(credential.nonce == sent.nonce)
        #expect(PKCE.challenge(for: credential.codeVerifier) == sent.challenge)
        #expect(credential.codeVerifier.count >= 43)
        #expect(openedScheme == Brand.urlScheme)
    }

    @Test func refusesACallbackForAnotherAttempt() async throws {
        let client = TelegramSignInClient(authorizationURL: { _, _, _ in URL(string: "https://api.example.test/start") }) { _, _ in
            URL(string: "tanishly://auth/telegram?code=CODE&state=SOMEONE-ELSES")!
        }
        await #expect(throws: TelegramSignInError.stateMismatch) { _ = try await client.signIn() }
    }

    @Test func withoutABackendDebugBuildsUseTheMockCredential() async throws {
        let client = TelegramSignInClient(authorizationURL: { _, _, _ in nil }) { _, _ in
            Issue.record("No browser session without a backend")
            return URL(string: "tanishly://")!
        }
        let credential = try await client.signIn()
        #expect(credential.code == "DEBUG-MOCK-TELEGRAM-CODE")
    }

    // MARK: Errors

    @Test func failuresReadAsTelegramSpecific() {
        #expect(SignInFailure.from(TelegramSignInError.stateMismatch, provider: .telegram).message.contains("Telegram"))
        #expect(SignInFailure.from(CancellationError(), provider: .telegram) == .telegramDidNotFinish)
    }
}
