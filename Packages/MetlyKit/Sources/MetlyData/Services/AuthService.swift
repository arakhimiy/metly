import Foundation
import MetlyCore
import MetlyNetworking
import Observation
import SwiftData

public enum AuthError: LocalizedError, Equatable {
    case missingIdentityToken

    public var errorDescription: String? {
        switch self {
        case .missingIdentityToken: "Sign in didn't return an identity token. Try again."
        }
    }
}

/// Sign in with Apple / Google → backend session (Keychain) → initial sync.
/// Sign-out and account deletion wipe the SwiftData store, the Keychain session, sync
/// bookkeeping and device preferences (SPEC §9 Q46).
@MainActor
@Observable
public final class AuthService: AuthServicing {
    public private(set) var isSignedIn: Bool
    public private(set) var accountEmail: String?
    public private(set) var userID: UUID?

    @ObservationIgnored private let api: any MetlyAPI
    @ObservationIgnored private let sessionStore: any SessionStore
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let sync: SyncEngine
    @ObservationIgnored private let isMock: Bool
    /// Set by the factory: realtime start/stop and push re-registration around session changes.
    @ObservationIgnored var onSignedIn: () -> Void = {}
    @ObservationIgnored var onSignedOut: () async -> Void = {}

    public init(api: any MetlyAPI, sessionStore: any SessionStore, container: ModelContainer, preferences: AppPreferences,
                sync: SyncEngine, isMock: Bool) {
        self.api = api
        self.sessionStore = sessionStore
        self.container = container
        self.preferences = preferences
        self.sync = sync
        self.isMock = isMock

        var session = sessionStore.load()
        // Mock mode with a local profile (demo data / earlier mock sign-in): keep the user signed in.
        if session == nil, isMock, container.mainContext.currentProfile() != nil {
            let mockSession = AuthSession(userID: MockSeed.ownerUserID, email: MockSeed.ownerEmail, accessToken: "mock-access",
                                          refreshToken: "mock-refresh", accessTokenExpiresAt: .distantFuture)
            try? sessionStore.save(mockSession)
            session = mockSession
        }
        isSignedIn = session != nil
        accountEmail = session?.email
        userID = session?.userID
    }

    // MARK: AuthServicing

    public func signIn(apple credential: AppleSignInCredential) async throws -> AuthResult {
        guard let tokenData = credential.identityToken, let identityToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.missingIdentityToken
        }
        let name = credential.fullName.map { PersonNameDTO(givenName: $0.givenName, familyName: $0.familyName) }
        let request = AppleSignInRequest(identityToken: identityToken,
                                         authorizationCode: credential.authorizationCode.flatMap { String(data: $0, encoding: .utf8) },
                                         userIdentifier: credential.userID, fullName: name, email: credential.email)
        let response = try await api.auth.signInWithApple(request)
        let suggested = response.suggestedName ?? name?.formatted
        return try await completeSignIn(response, suggestedName: suggested, fallbackEmail: credential.email)
    }

    public func signIn(google credential: GoogleSignInCredential) async throws -> AuthResult {
        let response = try await api.auth.signInWithGoogle(GoogleSignInRequest(idToken: credential.idToken))
        return try await completeSignIn(response, suggestedName: response.suggestedName ?? credential.fullName,
                                        fallbackEmail: credential.email)
    }

    public func signOut() async {
        let refreshToken = sessionStore.load()?.refreshToken
        if isSignedIn {
            // Best effort — never block local sign-out on the network.
            try? await api.auth.logout(LogoutRequest(refreshToken: refreshToken))
        }
        await wipeLocalAccount()
    }

    public func deleteAccount() async throws {
        try await api.account.deleteAccount()
        await wipeLocalAccount()
    }

    public func requestDataExport() async throws {
        _ = try await api.account.requestDataExport()
    }

    // MARK: Session lifecycle

    /// Called when the refresh token is rejected: the session is gone, local data stays until the
    /// next sign-in (wiped then if it's a different account).
    public func sessionDidExpire() {
        guard isSignedIn else { return }
        isSignedIn = false
        Task { await onSignedOut() }
    }

    private func completeSignIn(_ response: AuthResponse, suggestedName: String?, fallbackEmail: String?) async throws -> AuthResult {
        let context = container.mainContext
        // A different account than the one whose data is on this device → start clean.
        let previousUser = sync.state.lastUserID
        if let previousUser, previousUser != response.user.id {
            try? MetlyModelContainer.wipe(context)
            sync.reset()
        } else if previousUser == nil, !isMock {
            sync.state.cursor = nil   // first sign-in on this install: full snapshot
        }
        var session = AuthSession(tokens: response.session, user: response.user)
        if session.email == nil { session.email = fallbackEmail }
        try sessionStore.save(session)
        sync.state.lastUserID = response.user.id
        isSignedIn = true
        accountEmail = session.email
        userID = session.userID
        onSignedIn()

        // Returning users: bring their profile/cards down before deciding on setup.
        if !response.isNewUser { await sync.syncNow() }
        let profileComplete = response.user.profileComplete || context.currentProfile()?.isSetupComplete == true
        return AuthResult(needsSetup: !profileComplete, suggestedName: suggestedName, email: session.email)
    }

    private func wipeLocalAccount() async {
        await onSignedOut()
        sync.reset()
        try? MetlyModelContainer.wipe(container.mainContext)
        sessionStore.clear()
        preferences.reset()
        isSignedIn = false
        accountEmail = nil
        userID = nil
    }
}
