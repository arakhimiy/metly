import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData

/// Everything the app target injects at the root.
@MainActor
public struct MetlyEnvironment {
    public let services: AppServices
    public let client: MetlyClient
    public let syncEngine: SyncEngine
    public let auth: AuthService
    /// True when no backend URL is configured and `MockMetlyServer` answers every call.
    public var isMock: Bool { client.isMock }
}

/// Builds the live service graph for the app target.
///
/// Backend: Info.plist `MetlyAPIBaseURL` (or `-MetlyAPIBaseURL https://…`). Empty or an unresolved
/// `$(…)` → `MockMetlyServer`, seeded from the device store when one exists (so it mirrors the
/// device), with the demo account when launched with `-MetlyMockExistingAccount`, else empty.
public enum MetlyServiceFactory {
    @MainActor private static var cache: [ObjectIdentifier: MetlyEnvironment] = [:]

    /// Same graph as `makeEnvironment(container:).services` (kept for the app target).
    @MainActor public static func makeServices(container: ModelContainer) -> AppServices {
        makeEnvironment(container: container).services
    }

    /// Same graph as `makeEnvironment(container:).client` — inject with `.environment(client)`.
    @MainActor public static func makeClient(container: ModelContainer) -> MetlyClient {
        makeEnvironment(container: container).client
    }

    /// Builds (once per container) services, API client and sync engine sharing one session.
    @MainActor public static func makeEnvironment(container: ModelContainer,
                                                  baseURL: URL? = MetlyNetworking.configuredBaseURL()) -> MetlyEnvironment {
        let key = ObjectIdentifier(container)
        if let cached = cache[key] { return cached }

        let preferences = AppPreferences()
        let entitlements = Entitlements()
        let network = NetworkMonitor()
        let state = SyncStateStore()
        let relay = SessionRelay()

        let api: any MetlyAPI
        let mockServer: MockMetlyServer?
        let sessionStore: any SessionStore
        if let baseURL {
            sessionStore = KeychainSessionStore()
            let client = APIClient(baseURL: baseURL, sessionStore: sessionStore) {
                Task { @MainActor in relay.auth?.sessionDidExpire() }
            }
            api = LiveMetlyAPI(client: client)
            mockServer = nil
        } else {
            // Separate Keychain item so mock tokens never reach a real backend.
            sessionStore = KeychainSessionStore(service: "com.metly.app.session.mock")
            let seed: MockMetlyServer.Seed = if let snapshot = container.mainContext.mockAccountSnapshot(email: sessionStore.load()?.email) {
                .account(snapshot)
            } else if ProcessInfo.processInfo.arguments.contains("-MetlyMockExistingAccount") {
                .demo
            } else {
                .newAccount
            }
            let server = MockMetlyServer(seed: seed)
            api = server
            mockServer = server
        }

        let sync = SyncEngine(container: container, api: api, network: network, state: state)
        let auth = AuthService(api: api, sessionStore: sessionStore, container: container, preferences: preferences,
                               sync: sync, isMock: mockServer != nil)
        relay.auth = auth
        sync.shouldSync = { [weak auth] in auth?.isSignedIn ?? false }

        let client = MetlyClient(api: api, container: container, mockServer: mockServer)
        client.onSyncHint = { [weak sync] in sync?.requestSync() }

        let push = PushRegistrar(api: api, state: state)
        push.isSignedIn = { [weak auth] in auth?.isSignedIn ?? false }

        auth.onSignedIn = { [weak client, weak push] in
            client?.startRealtime()
            Task { await push?.registerPendingToken() }
        }
        auth.onSignedOut = { [weak client, weak push] in
            client?.stopRealtime()
            await push?.unregister()
        }

        let services = AppServices(auth: auth, sync: sync,
                                   deferredLinks: DeferredLinkService(api: api, state: state, isMock: mockServer != nil),
                                   subscriptions: SubscriptionVerifier(api: api, entitlements: entitlements), push: push,
                                   entitlements: entitlements, network: network, preferences: preferences)

        if auth.isSignedIn {
            client.startRealtime()
            Task { await push.registerPendingToken() }
        }

        let environment = MetlyEnvironment(services: services, client: client, syncEngine: sync, auth: auth)
        cache[key] = environment
        return environment
    }
}

/// Lets the `APIClient` (built first) reach the `AuthService` (built later) when a session dies.
@MainActor
private final class SessionRelay {
    weak var auth: AuthService?
}
