import Foundation
import MetlyCore
import MetlyNetworking
import Observation

/// DEFERRED_WELCOME: resolves "who shared their card before this install" once, on first launch.
/// The server matches a fingerprint (or an explicit token) against recent web "Get Tanishly" taps.
/// With `MockMetlyServer` an invite is returned only when launched with `-MetlyDeferredInvite`.
@MainActor
public final class DeferredLinkService: DeferredLinkServicing {
    private let api: any MetlyAPI
    private let state: SyncStateStore
    private let defaults: UserDefaults
    private let isMock: Bool

    public init(api: any MetlyAPI, state: SyncStateStore, defaults: UserDefaults = .standard, isMock: Bool) {
        self.api = api
        self.state = state
        self.defaults = defaults
        self.isMock = isMock
    }

    public func claimPendingInvite() async -> DeferredInvite? {
        let alwaysForDemo = isMock && ProcessInfo.processInfo.arguments.contains("-MetlyDeferredInvite")
        guard alwaysForDemo || !defaults.bool(forKey: Self.claimedKey) else { return nil }
        let request = DeferredLinkClaimRequest(installID: state.installID, fingerprint: Self.fingerprint())
        do {
            let invite = try await api.deferredLinks.claim(request)
            defaults.set(true, forKey: Self.claimedKey)
            return invite?.invite
        } catch {
            // Offline on first launch: try again next launch (until onboarding completes).
            return nil
        }
    }

    static let claimedKey = "deferredLink.claimed"

    static func fingerprint() -> DeviceFingerprint {
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
        }
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return DeviceFingerprint(model: model, osVersion: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                                 locale: Locale.current.identifier, timeZone: TimeZone.current.identifier,
                                 preferredLanguages: Array(Locale.preferredLanguages.prefix(3)))
    }
}

/// Sends StoreKit 2 transactions to the server; a server-confirmed Pro plan StoreKit doesn't see is
/// mirrored into `Entitlements` (StoreKit-derived values are never overridden).
@MainActor
public final class SubscriptionVerifier: SubscriptionVerifying {
    private let api: any MetlyAPI
    private let entitlements: Entitlements

    public init(api: any MetlyAPI, entitlements: Entitlements) {
        self.api = api
        self.entitlements = entitlements
    }

    public func verify(signedTransaction jws: String) async throws -> Plan {
        let entitlement = try await api.subscriptions.verify(VerifyTransactionRequest(signedTransaction: jws))
        apply(entitlement)
        return entitlement.plan
    }

    /// `GET /v1/me/entitlements` (e.g. on launch, after restore).
    @discardableResult
    public func refresh() async throws -> EntitlementDTO {
        let entitlement = try await api.subscriptions.fetchEntitlement()
        apply(entitlement)
        return entitlement
    }

    /// StoreKit stays the source of truth (`SubscriptionManager`): a reply — possibly for a superseded,
    /// expired or refunded transaction forwarded from `Transaction.updates` — never overrides a Pro plan
    /// StoreKit proves. It can only add Pro that StoreKit doesn't see (bought under another Apple ID);
    /// downgrades arrive through StoreKit itself.
    private func apply(_ entitlement: EntitlementDTO) {
        guard !entitlements.isPro, entitlement.plan == .pro else { return }
        entitlements.plan = entitlement.plan
        entitlements.productID = entitlement.productID
        entitlements.renewsAt = entitlement.renewsAt ?? entitlement.expiresAt
        entitlements.willRenew = entitlement.willRenew
    }
}

/// Registers the APNs token with the backend (`PUT /v1/me/devices/{installId}`). Tokens that
/// arrive before sign-in are kept and sent right after it.
@MainActor
public final class PushRegistrar: PushRegistering {
    private let api: any MetlyAPI
    private let state: SyncStateStore
    private let defaults: UserDefaults
    var isSignedIn: () -> Bool = { false }

    public init(api: any MetlyAPI, state: SyncStateStore, defaults: UserDefaults = .standard) {
        self.api = api
        self.state = state
        self.defaults = defaults
    }

    public func register(deviceToken: Data) async {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        defaults.set(hex, forKey: Keys.token)
        await registerPendingToken()
    }

    /// Sends the stored token if it changed since the last successful registration.
    public func registerPendingToken() async {
        guard isSignedIn(), let token = defaults.string(forKey: Keys.token),
              defaults.string(forKey: Keys.registered) != token else { return }
        let request = DeviceRegistrationRequest(deviceID: state.installID, apnsToken: token, apnsEnvironment: Self.apnsEnvironment,
                                                appVersion: APIClient.bundleVersion,
                                                osVersion: DeferredLinkService.fingerprint().osVersion,
                                                locale: Locale.current.identifier, timeZone: TimeZone.current.identifier)
        do {
            try await api.devices.registerDevice(request)
            defaults.set(token, forKey: Keys.registered)
        } catch {
            // Retried on the next launch / sign-in.
        }
    }

    /// Sign-out: stop pushes to this device for the old account.
    public func unregister() async {
        if defaults.string(forKey: Keys.registered) != nil {
            try? await api.devices.unregisterDevice(id: state.installID)
        }
        defaults.removeObject(forKey: Keys.registered)
    }

    static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }

    private enum Keys {
        static let token = "push.apnsToken"
        static let registered = "push.registeredToken"
    }
}
