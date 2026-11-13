// SyncEngine — the type, its state, requesting/joining/resetting passes and one pass's orchestration.
// The steps live in sibling extensions: +Push, +Pull, +Images, +Retry, +Background, +Observation.
import Foundation
import MetlyCore
import MetlyNetworking
import Observation
import SwiftData

/// Offline-first sync between SwiftData and the backend (docs/api/README.md § Sync protocol).
///
/// One pass = push dirty records (`POST /v1/sync/push`) → profile photo/logo uploads →
/// queued connect-request actions → pull deltas (`GET /v1/sync?since=`) → photo/logo and
/// connection avatar downloads.
/// Triggered (debounced) by local saves, app activation, connectivity returning, realtime
/// `sync.available`, the `app.tanishly.ios.sync` background task and `requestSync()` calls.
/// Pauses while offline; failures back off exponentially (2 s … 5 min).
///
/// Local deletes are held for `tombstoneGracePeriod` before their tombstone is pushed: the server's
/// confirmation hard-deletes the record, and the Undo toast (4 s) must still be able to restore it.
@MainActor
@Observable
public final class SyncEngine: SyncServicing {
    public static let backgroundTaskIdentifier = "app.tanishly.ios.sync"

    public internal(set) var status: SyncStatus = .idle
    public private(set) var lastSyncedAt: Date?
    /// Last entitlement the server reported. StoreKit stays the client's source of truth for the
    /// plan (FeatureProfile updates `Entitlements`); this is for diagnostics / server-side limits.
    public internal(set) var serverEntitlement: EntitlementDTO?

    @ObservationIgnored public let state: SyncStateStore
    /// Gate checked before every pass (wired to `AuthService.isSignedIn`).
    @ObservationIgnored public var shouldSync: () -> Bool = { true }
    @ObservationIgnored var debounceInterval: Duration
    @ObservationIgnored var pullPageSize = 500
    /// How long a local delete stays local (Undo window + margin) before its tombstone is pushed.
    @ObservationIgnored var tombstoneGracePeriod: TimeInterval = 6

    @ObservationIgnored let container: ModelContainer
    @ObservationIgnored let api: any MetlyAPI
    @ObservationIgnored let network: NetworkMonitor
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored var retryTask: Task<Void, Never>?
    @ObservationIgnored var heldTombstonesTask: Task<Void, Never>?
    /// When the tombstones the current pass held back fall due.
    @ObservationIgnored var heldTombstonesDue: Date?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored var failureCount = 0
    /// Bumped by `reset()`: a pass started before it never writes anything again.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored var observers: [any NSObjectProtocol] = []
    @ObservationIgnored static var backgroundTasksRegistered = false

    /// - Parameter observeChanges: listen to `ModelContext.didSave`, app activation and
    ///   connectivity (false in unit tests, which call `syncNow()` directly).
    public init(container: ModelContainer, api: any MetlyAPI, network: NetworkMonitor, state: SyncStateStore = SyncStateStore(),
                debounceInterval: Duration = .seconds(1.5), observeChanges: Bool = true) {
        self.container = container
        self.api = api
        self.network = network
        self.state = state
        self.debounceInterval = debounceInterval
        lastSyncedAt = state.lastSyncedAt
        if observeChanges { startObserving() }
    }

    // MARK: SyncServicing

    /// Coalesced: many calls within `debounceInterval` produce one pass.
    public func requestSync() {
        debounceTask?.cancel()
        let delay = debounceInterval
        debounceTask = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.syncNow()
        }
    }

    /// Runs a full pass now (or joins the running one and schedules one more pass after it).
    public func syncNow() async {
        await startPass().value
    }

    /// The running pass (asked for one more round), or a new one.
    func startPass() -> Task<Void, Never> {
        if let running {
            needsAnotherPass = true
            return running
        }
        let generation = generation
        let task = Task { [weak self] in
            guard let self else { return }
            repeat {
                self.needsAnotherPass = false
                await self.performSync()
            } while self.needsAnotherPass && self.status == .idle && self.generation == generation && !Task.isCancelled
            // After `reset()` a newer pass may own `running`.
            if self.generation == generation { self.running = nil }
        }
        running = task
        return task
    }

    /// Sign-out: stop everything and forget the cursor/bookkeeping. A pass still in flight is
    /// cancelled and never writes to the store or the bookkeeping again.
    public func reset() {
        generation += 1
        debounceTask?.cancel()
        retryTask?.cancel()
        heldTombstonesTask?.cancel()
        running?.cancel()
        debounceTask = nil
        retryTask = nil
        heldTombstonesTask = nil
        running = nil
        needsAnotherPass = false
        failureCount = 0
        state.reset()
        status = .idle
        lastSyncedAt = nil
        serverEntitlement = nil
    }

    // MARK: Pass

    private func performSync() async {
        let generation = generation
        guard shouldSync() else {
            status = .idle
            return
        }
        guard network.isOnline else {
            status = .offline
            return
        }
        status = .syncing
        heldTombstonesDue = nil
        do {
            try await pushRecords()
            try await pushConnectRequestActions()
            try await pull()
            try await syncImages()
            guard generation == self.generation else { return }
            let now = Date.now
            lastSyncedAt = now
            state.lastSyncedAt = now
            failureCount = 0
            retryTask?.cancel()
            retryTask = nil
            status = .idle
            scheduleBackgroundSync()
            scheduleHeldTombstones(due: heldTombstonesDue)
        } catch {
            // `reset()` (sign-out) happened while this pass was in flight: it owns nothing any more.
            guard generation == self.generation else { return }
            handle(APIError(error))
        }
    }

    /// Called after every `await` of a pass, before it writes: a cancelled pass (sign-out `reset()`,
    /// BGTask expiry) stops even when the response it was waiting for still arrives.
    func checkpoint() throws {
        try Task.checkCancellation()
    }

    private func handle(_ error: APIError) {
        switch error {
        case .cancelled:
            status = .idle
        case .unauthorized:
            status = .failed(String(localized: "Sign in again to sync your changes."))
        case .offline:
            status = .offline
            if network.isOnline { scheduleRetry() }   // server unreachable while the device is online
        default:
            status = .failed(error.localizedDescription)
            scheduleRetry()
        }
    }
}
