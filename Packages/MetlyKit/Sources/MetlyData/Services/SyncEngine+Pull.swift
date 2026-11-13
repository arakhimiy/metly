// SyncEngine — the pull half of a pass: paged deltas from the cursor (`GET /v1/sync?since=`), the
// snapshot restart on an expired cursor, reconciling after a snapshot, and noting server asset URLs.
import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData

extension SyncEngine {
    // MARK: Pull

    func pull() async throws {
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

    /// Server-owned asset URLs seen while applying records.
    func noteServerAssets(from applier: SyncApplier) {
        if let profile = applier.profile { state.noteRemoteImages(of: profile) }
        state.noteRemoteAvatars(applier.avatarURLs)
        state.forgetAvatars(applier.deletedConnectionIDs)
    }
}
