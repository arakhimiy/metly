import Foundation

// Service contracts used across modules. Implementations:
//  • AuthServicing, SyncServicing, DeferredLinkServicing, SubscriptionVerifying → MetlyData/MetlyNetworking (Data agent)
//  • Entitlements is updated by FeatureProfile's StoreKit manager.
// Features talk to these through `AppServices` (environment object).

public struct AppleSignInCredential: Sendable {
    public var userID: String
    public var identityToken: Data?
    public var authorizationCode: Data?
    public var fullName: PersonNameComponents?
    public var email: String?

    public init(userID: String, identityToken: Data?, authorizationCode: Data?, fullName: PersonNameComponents?, email: String?) {
        self.userID = userID
        self.identityToken = identityToken
        self.authorizationCode = authorizationCode
        self.fullName = fullName
        self.email = email
    }
}

public struct GoogleSignInCredential: Sendable {
    public var idToken: String
    public var accessToken: String?
    public var fullName: String?
    public var email: String?

    public init(idToken: String, accessToken: String?, fullName: String?, email: String?) {
        self.idToken = idToken
        self.accessToken = accessToken
        self.fullName = fullName
        self.email = email
    }
}

public struct AuthResult: Sendable {
    /// True when the account has no completed profile yet → go to setup.
    public var needsSetup: Bool
    /// Prefill for SETUP_PROFILE ("From your Apple ID").
    public var suggestedName: String?
    public var email: String?

    public init(needsSetup: Bool, suggestedName: String?, email: String?) {
        self.needsSetup = needsSetup
        self.suggestedName = suggestedName
        self.email = email
    }
}

@MainActor
public protocol AuthServicing: AnyObject {
    var isSignedIn: Bool { get }
    var accountEmail: String? { get }
    func signIn(apple: AppleSignInCredential) async throws -> AuthResult
    func signIn(google: GoogleSignInCredential) async throws -> AuthResult
    /// Wipes Keychain + local store.
    func signOut() async
    func deleteAccount() async throws
    /// "Download My Data" — server emails an export link.
    func requestDataExport() async throws
}

public enum SyncStatus: Equatable, Sendable {
    case idle
    case syncing
    case offline
    case failed(String)
}

@MainActor
public protocol SyncServicing: AnyObject {
    var status: SyncStatus { get }
    var lastSyncedAt: Date? { get }
    /// Push pending local changes and pull remote deltas. Safe to call often (coalesced).
    func requestSync()
    func syncNow() async
}

@MainActor
public protocol DeferredLinkServicing: AnyObject {
    /// Resolves an install attribution token once on first launch.
    func claimPendingInvite() async -> DeferredInvite?
}

@MainActor
public protocol SubscriptionVerifying: AnyObject {
    /// Sends a StoreKit 2 signed transaction (JWS) to the server; returns server-confirmed plan.
    func verify(signedTransaction jws: String) async throws -> Plan
}

@MainActor
public protocol PushRegistering: AnyObject {
    func register(deviceToken: Data) async
}
