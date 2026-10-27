import BackgroundTasks
import CryptoKit
import Foundation
import MetlyCore
import MetlyNetworking
import Observation
import SwiftData
import UIKit

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

    public private(set) var status: SyncStatus = .idle
    public private(set) var lastSyncedAt: Date?
    /// Last entitlement the server reported. StoreKit stays the client's source of truth for the
    /// plan (FeatureProfile updates `Entitlements`); this is for diagnostics / server-side limits.
    public private(set) var serverEntitlement: EntitlementDTO?

    @ObservationIgnored public let state: SyncStateStore
    /// Gate checked before every pass (wired to `AuthService.isSignedIn`).
    @ObservationIgnored public var shouldSync: () -> Bool = { true }
    @ObservationIgnored var debounceInterval: Duration
    @ObservationIgnored var pullPageSize = 500
    /// How long a local delete stays local (Undo window + margin) before its tombstone is pushed.
    @ObservationIgnored var tombstoneGracePeriod: TimeInterval = 6

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private let api: any MetlyAPI
    @ObservationIgnored private let network: NetworkMonitor
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var retryTask: Task<Void, Never>?
    @ObservationIgnored private var heldTombstonesTask: Task<Void, Never>?
    /// When the tombstones the current pass held back fall due.
    @ObservationIgnored private var heldTombstonesDue: Date?
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private var failureCount = 0
    /// Bumped by `reset()`: a pass started before it never writes anything again.
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private static var backgroundTasksRegistered = false

    /// Avatars are fetched this many at a time; bigger files are ignored.
    private static let avatarDownloadWidth = 4
    private static let maxAvatarBytes = 5_000_000

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
    private func startPass() -> Task<Void, Never> {
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

    // MARK: Background task (BGAppRefreshTask `app.tanishly.ios.sync`)

    /// Call once from the app target before launch finishes (e.g. `MetlyApp.init`).
    public func registerBackgroundTasks() {
        guard !Self.backgroundTasksRegistered else { return }
        Self.backgroundTasksRegistered = BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.backgroundTaskIdentifier,
                                                                         using: .main) { [weak self] task in
            MainActor.assumeIsolated {
                guard let self else {
                    task.setTaskCompleted(success: false)
                    return
                }
                self.runBackgroundTask(task)
            }
        }
    }

    /// Asks iOS for a background sync in ~15 min. Called after every successful pass; the app
    /// may also call it when entering the background.
    public func scheduleBackgroundSync(after interval: TimeInterval = 15 * 60) {
        guard Self.backgroundTasksRegistered else { return }
        let request = BGAppRefreshTaskRequest(identifier: Self.backgroundTaskIdentifier)
        request.earliestBeginDate = .now.addingTimeInterval(interval)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func runBackgroundTask(_ task: BGTask) {
        scheduleBackgroundSync()
        let work = backgroundPass()
        task.expirationHandler = { work.cancel() }
        Task { @MainActor in
            task.setTaskCompleted(success: await work.value)
        }
    }

    /// The work behind the BGTask. Cancelling it (expiration) cancels the pass itself — awaiting a
    /// pass doesn't react to cancellation — so `setTaskCompleted` is called before iOS kills the app.
    func backgroundPass() -> Task<Bool, Never> {
        Task { [weak self] () -> Bool in
            guard let self else { return false }
            let pass = self.startPass()
            await withTaskCancellationHandler {
                await pass.value
            } onCancel: {
                pass.cancel()
            }
            return !Task.isCancelled && self.status == .idle
        }
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
            try await pushProfileImages()
            try await pushConnectRequestActions()
            try await pull()
            try await pullProfileImages()
            try await pullConnectionAvatars()
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
    private func checkpoint() throws {
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

    private func scheduleRetry() {
        failureCount += 1
        let seconds = min(300, 2 * pow(2, Double(failureCount - 1))) * Double.random(in: 0.8...1.2)
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            await self?.syncNow()
        }
    }

    /// Held-back tombstones go out by themselves once their Undo window has passed. `due` comes from
    /// what the pass's push actually held back (one that fell due mid-pass still gets its pass).
    private func scheduleHeldTombstones(due: Date?) {
        heldTombstonesTask?.cancel()
        heldTombstonesTask = nil
        guard let due else { return }
        let delay = max(0, due.timeIntervalSinceNow) + 0.05
        heldTombstonesTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            await self?.syncNow()
        }
    }

    // MARK: Push

    private func pushRecords() async throws {
        let context = container.mainContext
        for _ in 0..<20 {
            let cutoff = Date.now.addingTimeInterval(-tombstoneGracePeriod)
            let batch = SyncPushBatch.collect(from: context, state: state, tombstonesDeletedBefore: cutoff)
            heldTombstonesDue = batch.earliestHeldDeletion?.addingTimeInterval(tombstoneGracePeriod)
            guard !batch.isEmpty else { return }
            let response = try await api.sync.push(SyncPushRequest(deviceID: state.installID, changes: batch.changes))
            try checkpoint()
            var applier = SyncApplier(context: context, mode: .echo(pushed: batch.pushed))
            applier.apply(response.records)
            _ = SyncApplier.resolve(applier.pendingLinks, in: context)
            noteServerAssets(from: applier)
            for result in response.results {
                switch result.status {
                case .rejected:
                    if let sent = batch.pushed[result.id] { state.markRejected(result.id, updatedAt: sent) }
                case .applied, .stale:
                    state.clearRejected(result.id)
                    if !applier.seenIDs.contains(result.id) { settle(result, batch: batch, applier: applier) }
                }
            }
            try context.save()
            guard batch.hasMore else { return }
        }
    }

    /// The server accepted a change but didn't echo it: settle the local copy if it's unchanged.
    private func settle(_ result: SyncResultDTO, batch: SyncPushBatch, applier: SyncApplier) {
        guard let local = applier.record(of: result.type, id: result.id), batch.pushed[result.id] == local.updatedAt else { return }
        switch local.syncState {
        case .pendingDelete: container.mainContext.delete(local)
        case .pendingUpsert: local.syncState = .synced
        case .synced: break
        }
    }

    /// Accept/decline/cancel done while offline are queued as local status changes.
    private func pushConnectRequestActions() async throws {
        let context = container.mainContext
        for request in SyncPushBatch.dirty(ConnectRequest.self, in: context) {
            let sentAt = request.updatedAt
            do {
                switch (request.syncState, request.direction, request.status) {
                case (.pendingDelete, .incoming, .pending):
                    _ = try? await api.connect.declineRequest(id: request.id)
                    try checkpoint()
                    context.delete(request)
                case (.pendingDelete, _, _):
                    context.delete(request)
                case (.pendingUpsert, .incoming, .accepted):
                    guard let cardID = request.myCardID ?? context.cardToShare()?.id else {
                        request.syncState = .synced
                        continue
                    }
                    let response = try await api.connect.acceptRequest(id: request.id, AcceptConnectRequest(cardID: cardID))
                    try checkpoint()
                    context.upsert(response.connection)
                    if request.updatedAt == sentAt { context.upsert(response.request) }
                case (.pendingUpsert, .incoming, .declined):
                    let response = try await api.connect.declineRequest(id: request.id)
                    try checkpoint()
                    if request.updatedAt == sentAt { context.upsert(response) }
                case (.pendingUpsert, .outgoing, .cancelled):
                    let response = try await api.connect.cancelRequest(id: request.id)
                    try checkpoint()
                    if request.updatedAt == sentAt { context.upsert(response) }
                default:
                    request.syncState = .synced
                }
            } catch let error as APIError where !error.isTransient && error != .unauthorized && error != .cancelled {
                // Expired / already answered elsewhere: take the server's view and move on.
                let canonical = try? await api.connect.fetchRequest(id: request.id)
                try checkpoint()
                if let canonical {
                    context.upsert(canonical)
                } else {
                    request.syncState = .synced
                }
            }
        }
        try context.save()
    }

    private func pushProfileImages() async throws {
        let context = container.mainContext
        // The server needs the profile record before an image can be attached to it.
        guard let profile = context.currentProfile(), profile.syncState == .synced else { return }
        for kind in ProfileImageKind.allCases {
            let data = kind == .photo ? profile.photoData : profile.logoData
            let localHash = data.map(Self.sha256)
            guard localHash != state.imageState(kind).syncedHash else { continue }
            let serverProfile: ProfileDTO
            if let data {
                let ticket = try await api.profile.requestImageUpload(kind, UploadTicketRequest(contentType: Self.contentType(of: data),
                                                                                                byteSize: data.count))
                try await api.profile.upload(data, using: ticket)
                serverProfile = try await api.profile.commitImageUpload(kind, uploadID: ticket.uploadID)
            } else {
                serverProfile = try await api.profile.deleteImage(kind)
            }
            try checkpoint()
            let url = kind == .photo ? serverProfile.photoURL : serverProfile.logoURL
            state.setImageState(SyncStateStore.ImageState(syncedHash: localHash, syncedURL: url, remoteURL: url), for: kind)
        }
    }

    // MARK: Pull

    private func pull() async throws {
        let context = container.mainContext
        var cursor = state.cursor
        var isSnapshot = cursor == nil
        var seen = Set<UUID>()
        var links: [SyncApplier.PendingLink] = []
        while true {
            let response: SyncPullResponse
            do {
                response = try await api.sync.pull(since: cursor, limit: pullPageSize)
            } catch let error as APIError where error.statusCode == 410 && cursor != nil {
                try checkpoint()
                // Cursor expired (tombstones purged): start over with a full snapshot.
                cursor = nil
                state.cursor = nil
                isSnapshot = true
                seen = []
                links = []
                continue
            }
            try checkpoint()
            var applier = SyncApplier(context: context, mode: .pull)
            applier.apply(response.changes)
            seen.formUnion(applier.seenIDs)
            // A parent can arrive pages after its children (pages follow the change sequence).
            links = SyncApplier.resolve(links + applier.pendingLinks, in: context)
            noteServerAssets(from: applier)
            if let entitlement = response.entitlement { serverEntitlement = entitlement }
            try context.save()
            cursor = response.cursor
            // A snapshot only counts once it's complete: until then the next pull starts it over,
            // otherwise `reconcile` would never run for it.
            if !isSnapshot { state.cursor = response.cursor }
            guard response.hasMore else { break }
        }
        if isSnapshot {
            try reconcile(keeping: seen)
            state.cursor = cursor
        }
    }

    /// After a full snapshot, synced local records the server no longer has were deleted while
    /// their tombstones were purged — remove them. Dirty records are kept (they'll be pushed).
    private func reconcile(keeping seen: Set<UUID>) throws {
        let context = container.mainContext
        func prune<Model: SyncedRecord>(_ type: Model.Type) throws {
            let descriptor = FetchDescriptor<Model>(predicate: Model.syncStatePredicate(SyncState.synced.rawValue, equal: true))
            for record in try context.fetch(descriptor) where !seen.contains(record.id) {
                context.delete(record)
            }
        }
        try prune(FollowUp.self)
        try prune(Connection.self)
        try prune(Event.self)
        try prune(Card.self)
        try prune(ConnectRequest.self)
        try prune(Profile.self)
        try context.save()
    }

    private func pullProfileImages() async throws {
        let context = container.mainContext
        guard let profile = context.currentProfile() else { return }
        var changed = false
        for kind in ProfileImageKind.allCases {
            var image = state.imageState(kind)
            let data = kind == .photo ? profile.photoData : profile.logoData
            // Only when there's no unsynced local change and the server has something new.
            guard data.map(Self.sha256) == image.syncedHash, image.remoteURL != image.syncedURL else { continue }
            var downloaded: Data?
            if let url = image.remoteURL {
                do {
                    downloaded = try await api.profile.downloadAsset(url)
                    try checkpoint()
                } catch let error as APIError where error.statusCode == 404 {
                    try checkpoint()
                    image.syncedURL = url   // gone — don't retry forever
                    state.setImageState(image, for: kind)
                    continue
                }
            }
            switch kind {
            case .photo: profile.photoData = downloaded
            case .logo: profile.logoData = downloaded
            }
            image.syncedHash = downloaded.map(Self.sha256)
            image.syncedURL = image.remoteURL
            state.setImageState(image, for: kind)
            changed = true
        }
        if changed { try context.save() }
    }

    /// Peers' profile photos (server-owned `avatarUrl`) → `Connection.avatarData`. Each URL is
    /// fetched once, a few at a time off the main actor; failures are retried on the next pass and
    /// never fail the sync. Only bytes put there by this method are ever cleared.
    private func pullConnectionAvatars() async throws {
        let context = container.mainContext
        var avatars = state.avatars
        var downloads: [(id: UUID, url: URL)] = []
        var changed = false
        for (id, avatar) in avatars where avatar.needsDownload {
            guard let connection = context.record(Connection.self, id: id), connection.deletedAt == nil else {
                avatars[id] = nil
                continue
            }
            if let url = avatar.remoteURL {
                downloads.append((id, url))
            } else {
                if avatar.syncedURL != nil, connection.avatarData != nil {
                    connection.avatarData = nil
                    changed = true
                }
                avatars[id] = nil
            }
        }

        if !downloads.isEmpty {
            let api = api
            let fetch: @Sendable (UUID, URL) async -> (UUID, URL, Result<Data, APIError>) = { id, url in
                do {
                    return (id, url, .success(try await api.profile.downloadAsset(url)))
                } catch {
                    return (id, url, .failure(APIError(error)))
                }
            }
            let results = await withTaskGroup(of: (UUID, URL, Result<Data, APIError>).self) { group in
                var queue = downloads[...]
                for _ in 0..<min(Self.avatarDownloadWidth, queue.count) {
                    let next = queue.removeFirst()
                    group.addTask { await fetch(next.id, next.url) }
                }
                var results: [(UUID, URL, Result<Data, APIError>)] = []
                for await result in group {
                    results.append(result)
                    if let next = queue.popFirst() {
                        group.addTask { await fetch(next.id, next.url) }
                    }
                }
                return results
            }
            try checkpoint()
            for (id, url, result) in results {
                switch result {
                case .success(let data):
                    guard let connection = context.record(Connection.self, id: id), connection.deletedAt == nil else {
                        avatars[id] = nil
                        continue
                    }
                    if data.count <= Self.maxAvatarBytes {
                        connection.avatarData = data
                        changed = true
                    }
                    avatars[id]?.syncedURL = url
                case .failure(let error) where error.statusCode == 404 || error.statusCode == 410:
                    avatars[id]?.syncedURL = url   // gone — don't retry forever
                case .failure:
                    break   // offline / server trouble: next pass
                }
            }
        }
        state.avatars = avatars
        if changed { try context.save() }
    }

    /// Server-owned asset URLs seen while applying records.
    private func noteServerAssets(from applier: SyncApplier) {
        if let profile = applier.profile { state.noteRemoteImages(of: profile) }
        state.noteRemoteAvatars(applier.avatarURLs)
        state.forgetAvatars(applier.deletedConnectionIDs)
    }

    // MARK: Observation

    private func startObserving() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.contextDidSave() }
        })
        observers.append(center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.requestSync() }
        })
        observeNetwork()
    }

    private func contextDidSave() {
        if hasPushableChanges() {
            requestSync()
        } else {
            // A fresh delete: push it once Undo is no longer offered.
            scheduleHeldTombstones(due: SyncPushBatch.nextHeldTombstone(in: container.mainContext, grace: tombstoneGracePeriod))
        }
    }

    private func observeNetwork() {
        withObservationTracking {
            _ = network.isOnline
        } onChange: { [weak self] in
            Task { @MainActor in self?.networkChanged() }
        }
    }

    private func networkChanged() {
        observeNetwork()
        if network.isOnline {
            if status != .idle || hasPushableChanges() { requestSync() }
        } else if status != .syncing {
            status = .offline
        }
    }

    /// True when something local needs pushing now (ignores records the server rejected and
    /// deletes still inside their Undo window).
    public func hasPushableChanges() -> Bool {
        let context = container.mainContext
        let state = state
        let cutoff = Date.now.addingTimeInterval(-tombstoneGracePeriod)
        func dirty<Model: SyncedRecord>(_ type: Model.Type) -> Bool {
            SyncPushBatch.dirty(type, in: context).contains { record in
                switch record.syncState {
                case .pendingDelete: SyncPushBatch.isDue(record, cutoff: cutoff)
                case .pendingUpsert: !state.isRejected(record.id, updatedAt: record.updatedAt)
                case .synced: false
                }
            }
        }
        return dirty(Profile.self) || dirty(Card.self) || dirty(Event.self) || dirty(Connection.self)
            || dirty(FollowUp.self) || !SyncPushBatch.dirty(ConnectRequest.self, in: context).isEmpty
    }

    // MARK: Helpers

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func contentType(of data: Data) -> String {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return "image/jpeg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "image/png" }
        if bytes.count >= 12, String(decoding: bytes[4..<12], as: UTF8.self).hasPrefix("ftypheic") { return "image/heic" }
        return "application/octet-stream"
    }
}
