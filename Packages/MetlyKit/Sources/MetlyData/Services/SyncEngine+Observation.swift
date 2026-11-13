// SyncEngine — what triggers a pass on its own: local saves, app activation and connectivity, and
// whether anything local needs pushing now.
import Foundation
import Observation
import SwiftData
import UIKit

extension SyncEngine {
    // MARK: Observation

    func startObserving() {
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
}
