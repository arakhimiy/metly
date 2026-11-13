// SyncEngine — the push half of a pass: dirty records in batches (`POST /v1/sync/push`), settling
// unechoed results, and connect-request actions queued while offline.
import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData

extension SyncEngine {
    // MARK: Push

    func pushRecords() async throws {
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
    func pushConnectRequestActions() async throws {
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
}
