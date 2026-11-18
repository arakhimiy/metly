import Foundation
import MetlyCore
import Testing
@testable import FeatureOnboarding

@Suite("Log In with Telegram")
@MainActor
struct TelegramLoginTests {
    // MARK: Callback parsing

    @Test func readsCodeWhenStateMatches() throws {
        let url = try #require(URL(string: "nameshake://auth/telegram?code=abc123&state=S1"))
        #expect(try TelegramAuthorizationResponse.code(from: url, expectedState: "S1") == "abc123")
    }

    @Test func rejectsForeignStateAndMissingCode() throws {
        let forged = try #require(URL(string: "nameshake://auth/telegram?code=abc&state=OTHER"))
        #expect(throws: TelegramSignInError.stateMismatch) { try TelegramAuthorizationResponse.code(from: forged, expectedState: "S1") }
        let empty = try #require(URL(string: "nameshake://auth/telegram?state=S1"))
        #expect(throws: TelegramSignInError.missingCode) { try TelegramAuthorizationResponse.code(from: empty, expectedState: "S1") }
    }

    @Test func declinedConsentIsACancellationOtherErrorsAreNot() throws {
        let declined = try #require(URL(string: "nameshake://auth/telegram?error=access_denied&state=S1"))
        #expect(throws: TelegramSignInError.cancelled) { try TelegramAuthorizationResponse.code(from: declined, expectedState: "S1") }
        let unavailable = try #require(URL(string: "nameshake://auth/telegram?error=temporarily_unavailable&state=S1"))
        #expect(throws: TelegramSignInError.notConfigured) { try TelegramAuthorizationResponse.code(from: unavailable, expectedState: "S1") }
        let broken = try #require(URL(string: "nameshake://auth/telegram?error=invalid_request"))
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
            return URL(string: "nameshake://auth/telegram?code=CODE&state=\(seen?.state ?? "")")!
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
            URL(string: "nameshake://auth/telegram?code=CODE&state=SOMEONE-ELSES")!
        }
        await #expect(throws: TelegramSignInError.stateMismatch) { _ = try await client.signIn() }
    }

    @Test func withoutABackendDebugBuildsUseTheMockCredential() async throws {
        let client = TelegramSignInClient(authorizationURL: { _, _, _ in nil }) { _, _ in
            Issue.record("No browser session without a backend")
            return URL(string: "nameshake://")!
        }
        let credential = try await client.signIn()
        #expect(credential.code == "DEBUG-MOCK-TELEGRAM-CODE")
    }

    // MARK: Telegram app flow

    private func appClient(
        installed: Bool = true,
        link: URL? = URL(string: "tg://oauth?token=T"),
        opens: Bool = true,
        returns: @escaping @MainActor (_ state: String) -> URL?,
        receiver: TelegramAppReturn,
        browserUsed: @escaping @MainActor () -> Void = {}
    ) -> TelegramSignInClient {
        var sentState = ""
        var client = TelegramSignInClient(authorizationURL: { _, state, _ in
            sentState = state
            return URL(string: "https://api.example.test/v1/auth/telegram/authorize")
        }) { _, _ in
            browserUsed()
            return URL(string: "nameshake://auth/telegram?code=WEBCODE&state=\(sentState)")!
        }
        client.telegramAppInstalled = { installed }
        client.appLink = { _, _, _ in link }
        client.telegramReturn = receiver
        client.openTelegram = { _ in
            guard opens else { return false }
            // Telegram approves and reopens the app through its Universal Link.
            Task { @MainActor in
                if let url = returns(sentState) { receiver.handle(url) }
            }
            return true
        }
        return client
    }

    @Test func signsInThroughTheTelegramAppWhenItIsInstalled() async throws {
        let receiver = TelegramAppReturn()
        var browserUsed = false
        let client = appClient(returns: { URL(string: "https://app1-login.tg.dev?code=APPCODE&state=\($0)") },
                               receiver: receiver, browserUsed: { browserUsed = true })
        let credential = try await client.signIn()
        #expect(credential.code == "APPCODE")
        #expect(credential.flow == .app)
        #expect(!browserUsed)
    }

    @Test func acceptsATelegramReturnWithoutStateButNotAForeignOne() async throws {
        let receiver = TelegramAppReturn()
        let bare = appClient(returns: { _ in URL(string: "https://app1-login.tg.dev?code=APPCODE") }, receiver: receiver)
        #expect(try await bare.signIn().code == "APPCODE")

        let forged = appClient(returns: { _ in URL(string: "https://app1-login.tg.dev?code=APPCODE&state=OTHER") }, receiver: receiver)
        await #expect(throws: TelegramSignInError.stateMismatch) { _ = try await forged.signIn() }
    }

    @Test func fallsBackToTheBrowserWithoutTheTelegramApp() async throws {
        for client in [
            appClient(installed: false, returns: { _ in nil }, receiver: TelegramAppReturn()),
            appClient(link: nil, returns: { _ in nil }, receiver: TelegramAppReturn()),
            appClient(opens: false, returns: { _ in nil }, receiver: TelegramAppReturn()),
        ] {
            let credential = try await client.signIn()
            #expect(credential.code == "WEBCODE")
            #expect(credential.flow == .web)
        }
    }

    @Test func comingBackWithoutApprovingCancels() async throws {
        let receiver = TelegramAppReturn()
        receiver.graceAfterReturn = .milliseconds(10)
        let client = appClient(returns: { _ in
            // The user returns from Telegram by hand: no link, the app just becomes active again.
            receiver.appDidLeave()
            receiver.appDidBecomeActive()
            return nil
        }, receiver: receiver)
        await #expect(throws: TelegramSignInError.cancelled) { _ = try await client.signIn() }
    }

    @Test func onlyTelegramLoginLinksAreClaimed() throws {
        #expect(TelegramAppReturn.isTelegramReturn(try #require(URL(string: "https://app123-login.tg.dev?code=x"))))
        #expect(!TelegramAppReturn.isTelegramReturn(try #require(URL(string: "https://nameshake.app/c/abc"))))
        #expect(!TelegramAppReturn.isTelegramReturn(try #require(URL(string: "nameshake://auth/telegram?code=x"))))
        #expect(!TelegramAppReturn().handle(try #require(URL(string: "https://nameshake.app/c/abc"))))
    }

    // MARK: Errors

    @Test func failuresReadAsTelegramSpecific() {
        #expect(SignInFailure.from(TelegramSignInError.stateMismatch, provider: .telegram).message.contains("Telegram"))
        #expect(SignInFailure.from(CancellationError(), provider: .telegram) == .telegramDidNotFinish)
    }
}
