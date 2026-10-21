import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import Synchronization
@testable import MetlyData

/// In-memory store + instant mock server + a sync engine that only runs when asked.
@MainActor
struct SyncHarness {
    let container: ModelContainer
    let server: MockMetlyServer
    let engine: SyncEngine
    let state: SyncStateStore
    let network: NetworkMonitor

    var context: ModelContext { container.mainContext }

    /// - Parameter hooks: route the engine's calls through `HookedAPI` (slow / failing sync calls).
    init(local: PreviewSeed.Variant = .signedOut, server seed: MockMetlyServer.Seed = .demo, online: Bool = true,
         hooks: HookedAPI.Hooks? = nil) throws {
        container = try MetlyModelContainer.make(inMemory: true)
        PreviewSeed.insert(local, into: container.mainContext)
        let server = MockMetlyServer(seed: seed, configuration: .instant)
        self.server = server
        state = SyncStateStore(defaults: UserDefaults(suiteName: "metly.tests.\(UUID().uuidString)")!)
        network = NetworkMonitor(simulatedOnline: online)
        let api: any MetlyAPI = if let hooks { HookedAPI(server: server, hooks: hooks) } else { server }
        engine = SyncEngine(container: container, api: api, network: network, state: state, observeChanges: false)
        // Protocol tests expect deletes to go out on the next pass; the Undo window has its own tests.
        engine.tombstoneGracePeriod = 0
    }

    func all<Model: PersistentModel>(_ type: Model.Type) -> [Model] {
        (try? context.fetch(FetchDescriptor<Model>())) ?? []
    }

    func count<Model: PersistentModel>(_ type: Model.Type) -> Int { all(type).count }

    func connection(_ id: UUID) -> Connection? { context.record(Connection.self, id: id) }
}

enum TestImage {
    /// Minimal JPEG-looking bytes (magic number is all the content-type sniffing needs).
    static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x02, 0x03])
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D])
}

/// A one-shot latch: `wait()` suspends until `open()` — deliberately ignoring task cancellation, like a
/// network response that is already on its way back.
final class Gate: Sendable {
    private let state = Mutex<(isOpen: Bool, waiters: [CheckedContinuation<Void, Never>])>((false, []))

    func open() {
        let waiters = state.withLock { state -> [CheckedContinuation<Void, Never>] in
            state.isOpen = true
            defer { state.waiters = [] }
            return state.waiters
        }
        for waiter in waiters { waiter.resume() }
    }

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let resumeNow = state.withLock { state -> Bool in
                if state.isOpen { return true }
                state.waiters.append(continuation)
                return false
            }
            if resumeNow { continuation.resume() }
        }
    }

    var isOpen: Bool { state.withLock { $0.isOpen } }
}

/// Polls `condition` (main actor) until it holds or `timeout` passes.
@MainActor
func eventually(timeout: Duration = .seconds(3), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}

/// `MockMetlyServer` with hooks in front of `sync.pull`, and a call log for auth/devices.
/// `revokesOnLogout` makes authenticated calls after `logout` fail like a real server would.
struct HookedAPI: MetlyAPI {
    final class Hooks: Sendable {
        typealias PullHook = @Sendable (_ call: Int) async throws -> Void
        private let pullHook = Mutex<PullHook?>(nil)
        private let pulls = Mutex(0)
        private let calls = Mutex<[String]>([])
        private let loggedOut = Mutex(false)
        let revokesOnLogout: Bool

        init(revokesOnLogout: Bool = false, beforePull: PullHook? = nil) {
            self.revokesOnLogout = revokesOnLogout
            pullHook.withLock { $0 = beforePull }
        }

        func setBeforePull(_ hook: PullHook?) { pullHook.withLock { $0 = hook } }

        typealias CallHook = @Sendable () async throws -> Void
        private let logoutHook = Mutex<CallHook?>(nil)
        func setBeforeLogout(_ hook: CallHook?) { logoutHook.withLock { $0 = hook } }
        fileprivate func willLogOut() async throws {
            if let hook = logoutHook.withLock({ $0 }) { try await hook() }
        }

        var pullCount: Int { pulls.withLock { $0 } }
        var log: [String] { calls.withLock { $0 } }

        fileprivate func willPull() async throws {
            let call = pulls.withLock { count -> Int in
                count += 1
                return count
            }
            if let hook = pullHook.withLock({ $0 }) { try await hook(call) }
        }

        fileprivate func record(_ call: String) { calls.withLock { $0.append(call) } }
        fileprivate func logOut() { loggedOut.withLock { $0 = true } }
        fileprivate func logIn() { loggedOut.withLock { $0 = false } }
        fileprivate func requireSession() throws {
            if revokesOnLogout, loggedOut.withLock({ $0 }) { throw APIError.unauthorized }
        }
    }

    let server: MockMetlyServer
    let hooks: Hooks

    var auth: any AuthAPI { HookedAuth(server: server, hooks: hooks) }
    var account: any AccountAPI { server }
    var profile: any ProfileAPI { server }
    var cards: any CardsAPI { server }
    var wallet: any WalletAPI { server }
    var connections: any ConnectionsAPI { server }
    var blocks: any BlocksAPI { server }
    var followUps: any FollowUpsAPI { server }
    var events: any EventsAPI { server }
    var connect: any ConnectAPI { server }
    var realtime: any RealtimeAPI { server }
    var publicProfiles: any PublicProfilesAPI { server }
    var deferredLinks: any DeferredLinksAPI { server }
    var subscriptions: any SubscriptionsAPI { server }
    var devices: any DevicesAPI { HookedDevices(server: server, hooks: hooks) }
    var sync: any SyncAPI { HookedSync(server: server, hooks: hooks) }
}

private struct HookedSync: SyncAPI {
    let server: MockMetlyServer
    let hooks: HookedAPI.Hooks

    func push(_ request: SyncPushRequest) async throws -> SyncPushResponse {
        try await server.push(request)
    }

    func pull(since cursor: String?, limit: Int) async throws -> SyncPullResponse {
        try await hooks.willPull()
        return try await server.pull(since: cursor, limit: limit)
    }
}

private struct HookedAuth: AuthAPI {
    let server: MockMetlyServer
    let hooks: HookedAPI.Hooks

    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse {
        hooks.logIn()
        return try await server.signInWithApple(request)
    }

    func signInWithGoogle(_ request: GoogleSignInRequest) async throws -> AuthResponse {
        hooks.logIn()
        return try await server.signInWithGoogle(request)
    }

    func logout(_ request: LogoutRequest) async throws {
        try await hooks.willLogOut()
        try hooks.requireSession()
        try await server.logout(request)
        hooks.record("logout")
        hooks.logOut()
    }
}

private struct HookedDevices: DevicesAPI {
    let server: MockMetlyServer
    let hooks: HookedAPI.Hooks

    func registerDevice(_ request: DeviceRegistrationRequest) async throws {
        try hooks.requireSession()
        try await server.registerDevice(request)
        hooks.record("registerDevice")
    }

    func unregisterDevice(id: String) async throws {
        try hooks.requireSession()
        try await server.unregisterDevice(id: id)
        hooks.record("unregisterDevice")
    }
}
