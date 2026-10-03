import Foundation
import Network
import Observation

/// Dependency container injected at the root with `.environment(services)`.
/// Read with `@Environment(AppServices.self) private var services`.
@MainActor
@Observable
public final class AppServices {
    public var auth: any AuthServicing
    public var sync: any SyncServicing
    public var deferredLinks: any DeferredLinkServicing
    public var subscriptions: any SubscriptionVerifying
    public var push: any PushRegistering
    public let entitlements: Entitlements
    public let network: NetworkMonitor
    public let preferences: AppPreferences

    public init(auth: any AuthServicing,
                sync: any SyncServicing,
                deferredLinks: any DeferredLinkServicing,
                subscriptions: any SubscriptionVerifying,
                push: any PushRegistering,
                entitlements: Entitlements = Entitlements(),
                network: NetworkMonitor = NetworkMonitor(),
                preferences: AppPreferences = AppPreferences()) {
        self.auth = auth
        self.sync = sync
        self.deferredLinks = deferredLinks
        self.subscriptions = subscriptions
        self.push = push
        self.entitlements = entitlements
        self.network = network
        self.preferences = preferences
    }

    /// In-memory stand-ins for SwiftUI previews and tests.
    public static func preview(plan: Plan = .free, online: Bool = true) -> AppServices {
        let stub = PreviewServiceStub()
        let services = AppServices(auth: stub, sync: stub, deferredLinks: stub, subscriptions: stub, push: stub,
                                   entitlements: Entitlements(plan: plan),
                                   network: NetworkMonitor(simulatedOnline: online),
                                   preferences: AppPreferences(store: UserDefaults(suiteName: "preview") ?? .standard))
        return services
    }
}

/// Current plan + limits. Updated by FeatureProfile's StoreKit manager.
@MainActor
@Observable
public final class Entitlements {
    public var plan: Plan
    public var productID: String?
    public var renewsAt: Date?
    public var willRenew: Bool = false

    public init(plan: Plan = .free) { self.plan = plan }

    public var limits: PlanLimits { plan == .pro ? .pro : .free }
    public var isPro: Bool { plan == .pro }
}

/// Reachability (`NWPathMonitor`). Drives offline banners and the sync engine.
@MainActor
@Observable
public final class NetworkMonitor {
    public private(set) var isOnline: Bool = true
    @ObservationIgnored private let monitor: NWPathMonitor?

    public init() {
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: DispatchQueue(label: "metly.network-monitor"))
    }

    public init(simulatedOnline: Bool) {
        monitor = nil
        isOnline = simulatedOnline
    }

    deinit { monitor?.cancel() }
}

/// Small device-local preferences (not synced). Server-synced settings live on `Profile` in MetlyData.
@MainActor
@Observable
public final class AppPreferences {
    @ObservationIgnored private let store: UserDefaults

    public var appearance: AppAppearance {
        didSet { store.set(appearance.rawValue, forKey: Keys.appearance) }
    }
    public var hasCompletedOnboarding: Bool {
        didSet { store.set(hasCompletedOnboarding, forKey: Keys.onboarding) }
    }
    /// Index of the card shown in the Home carousel.
    public var activeCardID: UUID? {
        didSet { store.set(activeCardID?.uuidString, forKey: Keys.activeCard) }
    }
    /// JUST_MET heuristic: when the QR was last shown fullscreen.
    public var lastQRShownAt: Date? {
        didSet { store.set(lastQRShownAt, forKey: Keys.lastQR) }
    }

    public init(store: UserDefaults = .standard) {
        self.store = store
        appearance = AppAppearance(rawValue: store.string(forKey: Keys.appearance) ?? "") ?? .system
        hasCompletedOnboarding = store.bool(forKey: Keys.onboarding)
        activeCardID = store.string(forKey: Keys.activeCard).flatMap(UUID.init(uuidString:))
        lastQRShownAt = store.object(forKey: Keys.lastQR) as? Date
    }

    public func reset() {
        appearance = .system
        hasCompletedOnboarding = false
        activeCardID = nil
        lastQRShownAt = nil
    }

    private enum Keys {
        static let appearance = "pref.appearance"
        static let onboarding = "pref.onboardingDone"
        static let activeCard = "pref.activeCardID"
        static let lastQR = "pref.lastQRShownAt"
    }
}

/// No-op implementation for previews/tests.
@MainActor
final class PreviewServiceStub: AuthServicing, SyncServicing, DeferredLinkServicing, SubscriptionVerifying, PushRegistering {
    var isSignedIn = true
    var accountEmail: String? = "aziza@tezkor.uz"
    var status: SyncStatus = .idle
    var lastSyncedAt: Date? = .now

    func signIn(apple: AppleSignInCredential) async throws -> AuthResult { AuthResult(needsSetup: true, suggestedName: "Aziza Karimova", email: accountEmail) }
    func signIn(google: GoogleSignInCredential) async throws -> AuthResult { AuthResult(needsSetup: true, suggestedName: google.fullName, email: google.email) }
    func signOut() async { isSignedIn = false }
    func deleteAccount() async throws { isSignedIn = false }
    func requestDataExport() async throws {}
    func requestSync() {}
    func syncNow() async {}
    func claimPendingInvite() async -> DeferredInvite? { nil }
    func verify(signedTransaction jws: String) async throws -> Plan { .pro }
    func register(deviceToken: Data) async {}
}
