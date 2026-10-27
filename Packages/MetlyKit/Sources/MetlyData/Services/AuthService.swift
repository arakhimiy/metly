import AuthenticationServices
import Foundation
import MetlyCore
import MetlyNetworking
import Observation
import SwiftData

public enum AuthError: LocalizedError, Equatable {
    case missingIdentityToken

    public var errorDescription: String? {
        switch self {
        case .missingIdentityToken: String(localized: "Sign in didn't return an identity token. Try again.")
        }
    }
}

/// Sign in with Apple / Google → backend session (Keychain) → initial sync.
///
/// - `isSignedIn` depends only on the Keychain session (a signed-in user who hasn't finished
///   setup stays signed in across launches).
/// - Sign-out and account deletion wipe the Keychain session, sync bookkeeping, device
///   preferences and — as the very last step, with no `await` after it — the SwiftData store.
/// - When the session dies on its own (refresh token rejected, Apple ID revoked) `isSignedIn`
///   flips to false without wiping: the app shell routes to onboarding, then calls `signOut()`.
@MainActor
@Observable
public final class AuthService: AuthServicing {
    public private(set) var isSignedIn: Bool
    public private(set) var accountEmail: String?
    public private(set) var userID: UUID?
    /// Set when Apple reported the credential revoked (notification or launch check).
    public private(set) var appleCredentialRevoked = false

    @ObservationIgnored private let api: any MetlyAPI
    @ObservationIgnored private let sessionStore: any SessionStore
    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let preferences: AppPreferences
    @ObservationIgnored private let sync: SyncEngine
    @ObservationIgnored private let isMock: Bool
    @ObservationIgnored private var revocationObserver: (any NSObjectProtocol)?
    /// Set by the factory: realtime start/stop and push (un)registration around session changes.
    @ObservationIgnored var onSignedIn: () -> Void = {}
    @ObservationIgnored var onSignedOut: () async -> Void = {}
    /// Upper bound for sign-out's network clean-up (push unregistration + logout).
    @ObservationIgnored var signOutNetworkTimeout: Duration = .seconds(10)
    @ObservationIgnored private var signingOut: Task<Void, Never>?

    public init(api: any MetlyAPI, sessionStore: any SessionStore, container: ModelContainer, preferences: AppPreferences,
                sync: SyncEngine, isMock: Bool, observeRevocation: Bool = true) {
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

        if observeRevocation {
            revocationObserver = NotificationCenter.default.addObserver(
                forName: ASAuthorizationAppleIDProvider.credentialRevokedNotification, object: nil, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.credentialWasRevoked() }
            }
        }
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
        return try await completeSignIn(response, suggestedName: suggested, fallbackEmail: credential.email,
                                        appleUserID: credential.userID)
    }

    public func signIn(google credential: GoogleSignInCredential) async throws -> AuthResult {
        let response = try await api.auth.signInWithGoogle(GoogleSignInRequest(idToken: credential.idToken))
        return try await completeSignIn(response, suggestedName: response.suggestedName ?? credential.fullName,
                                        fallbackEmail: credential.email, appleUserID: nil)
    }

    #if DEBUG
    public var supportsTestSignIn: Bool { !isMock }

    /// Same account for the same name, so a reinstall signs back into it.
    public func signInForDevelopment(name: String) async throws -> AuthResult {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let subject = "ios-" + trimmed.lowercased().filter { $0.isLetter || $0.isNumber }
        let response = try await api.auth.signInForDevelopment(DevSignInRequest(subject: subject, fullName: trimmed))
        return try await completeSignIn(response, suggestedName: response.suggestedName ?? trimmed, fallbackEmail: nil,
                                        appleUserID: nil)
    }
    #endif

    /// Safe to call more than once (the UI also wipes defensively); concurrent calls share one sign-out.
    /// The UI shows onboarding before this returns, so a new sign-in may start meanwhile: it waits
    /// for this sign-out to finish (`completeSignIn`), so the late wipe can't erase the new session.
    public func signOut() async {
        if let signingOut { return await signingOut.value }
        let task = Task {
            await self.performSignOut()
            self.signingOut = nil
        }
        signingOut = task
        await task.value
    }

    private func performSignOut() async {
        let refreshToken = sessionStore.load()?.refreshToken
        let hadSession = isSignedIn && refreshToken != nil
        // Push unregistration needs a working session, and logout revokes it: unregister first,
        // or this device keeps receiving the old account's notifications. Both are best effort and
        // bounded — a slow server never keeps the device half signed out.
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.endServerSession(revoking: hadSession ? refreshToken : nil) }
            group.addTask { [limit = signOutNetworkTimeout] in try? await Task.sleep(for: limit) }
            await group.next()
            group.cancelAll()
        }
        wipeLocalAccount()
    }

    private func endServerSession(revoking refreshToken: String?) async {
        await onSignedOut()
        if let refreshToken {
            try? await api.auth.logout(LogoutRequest(refreshToken: refreshToken))
        }
    }

    public func deleteAccount() async throws {
        try await api.account.deleteAccount()
        await onSignedOut()
        wipeLocalAccount()
    }

    public func requestDataExport() async throws {
        _ = try await api.account.requestDataExport()
    }

    // MARK: Sign in with Apple revocation

    /// Call at launch while signed in. Returns false when the Apple ID credential was revoked or
    /// no longer exists — then route to onboarding and call `signOut()`. Google sessions, offline
    /// checks and errors count as valid.
    public func checkAppleCredentialState() async -> Bool {
        guard isSignedIn, let appleUserID = sessionStore.load()?.appleUserID else { return true }
        guard let state = try? await ASAuthorizationAppleIDProvider().credentialState(forUserID: appleUserID) else { return true }
        switch state {
        case .revoked:
            credentialWasRevoked()
            return false
        case .notFound where !isMock:   // simulator mock sign-ins may use made-up Apple IDs
            credentialWasRevoked()
            return false
        default:
            return true
        }
    }

    private func credentialWasRevoked() {
        guard isSignedIn, sessionStore.load()?.appleUserID != nil else { return }
        appleCredentialRevoked = true
        endSessionWithoutWipe()
    }

    // MARK: Session lifecycle

    /// The refresh token was rejected: the session is gone; local data stays until `signOut()`
    /// (or the next sign-in, which wipes first if it's a different account).
    public func sessionDidExpire() {
        endSessionWithoutWipe()
    }

    private func endSessionWithoutWipe() {
        guard isSignedIn else { return }
        isSignedIn = false
        Task { await onSignedOut() }
    }

    private func completeSignIn(_ response: AuthResponse, suggestedName: String?, fallbackEmail: String?,
                                appleUserID: String?) async throws -> AuthResult {
        // A sign-out still talking to the server would otherwise wipe this new session when it ends.
        if let signingOut { await signingOut.value }
        let context = container.mainContext
        // A different account than the one whose data is on this device → start clean.
        let previousUser = sync.state.lastUserID
        if let previousUser, previousUser != response.user.id {
            sync.reset()
            try? MetlyModelContainer.wipe(context)
        } else if previousUser == nil, !isMock {
            sync.state.cursor = nil   // first sign-in on this install: full snapshot
        }
        var session = AuthSession(tokens: response.session, user: response.user, appleUserID: appleUserID)
        if session.email == nil { session.email = fallbackEmail }
        try sessionStore.save(session)
        sync.state.lastUserID = response.user.id
        isSignedIn = true
        appleCredentialRevoked = false
        accountEmail = session.email
        userID = session.userID
        onSignedIn()

        // Returning users: bring their profile/cards down before deciding on setup.
        if !response.isNewUser { await sync.syncNow() }
        let profileComplete = response.user.profileComplete || context.currentProfile()?.isSetupComplete == true
        return AuthResult(needsSetup: !profileComplete, suggestedName: suggestedName, email: session.email)
    }

    /// Synchronous on purpose: nothing can interleave between stopping sync and wiping the store.
    private func wipeLocalAccount() {
        sync.reset()
        sessionStore.clear()
        preferences.reset()
        isSignedIn = false
        accountEmail = nil
        userID = nil
        try? MetlyModelContainer.wipe(container.mainContext)
    }
}
