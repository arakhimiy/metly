import Foundation
import SwiftData
import UIKit
import WidgetKit

/// The app's data, as the publisher needs it. Implemented in the app target over SwiftData
/// (`AppWidgetSnapshotSource`), so this module — linked by the widget extension — never imports MetlyData.
@MainActor
public protocol WidgetSnapshotSource: AnyObject {
    /// Current values, or nil when signed out / setup not finished.
    func snapshotInput(now: Date) -> WidgetSnapshotInput?

    /// Marks these follow-ups done (`isDone`, `completedAt`, `markChanged()`, one save).
    /// Returns the ids that are settled — applied, already done, deleted or unknown — so their queue
    /// entries can be dropped. Ids left out stay queued and are retried on the next activation.
    func completeFollowUps(_ completions: [WidgetFollowUpCompletion]) -> Set<UUID>
}

/// App-side engine that keeps the widgets current.
///
/// • Republishes (debounced) whenever any `ModelContext` saves — UI edits, capture flows, sync — and when
///   the app becomes active.
/// • Before every publish it drains the widget action queue (Follow-ups "Done" taps) into the store.
/// • Writes `snapshot.json` and reloads widget timelines only when the content actually changed,
///   which keeps WidgetKit's reload budget for real changes.
///
/// The app calls `start(source:)` once at launch.
@MainActor
public final class WidgetSnapshotPublisher {
    public private(set) static var shared: WidgetSnapshotPublisher?

    private let source: any WidgetSnapshotSource
    private let store: WidgetSnapshotStore
    private let debounce: Duration
    private let reloadTimelines: @MainActor () -> Void
    private let now: @MainActor () -> Date
    private let thumbnails = WidgetThumbnailCache()
    private var observers: [any NSObjectProtocol] = []
    private var pendingPublish: Task<Void, Never>?
    private var isPublishing = false

    public init(source: any WidgetSnapshotSource, store: WidgetSnapshotStore = .appGroup,
                debounce: Duration = .milliseconds(500),
                now: @escaping @MainActor () -> Date = { .now },
                reloadTimelines: @escaping @MainActor () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.source = source
        self.store = store
        self.debounce = debounce
        self.now = now
        self.reloadTimelines = reloadTimelines
    }

    /// Starts observing and publishes once (idempotent). Call from `App.init` after the store exists.
    @discardableResult
    public static func start(source: any WidgetSnapshotSource, store: WidgetSnapshotStore = .appGroup) -> WidgetSnapshotPublisher {
        if let shared { return shared }
        let publisher = WidgetSnapshotPublisher(source: source, store: store)
        shared = publisher
        publisher.observe()
        publisher.setNeedsPublish()
        return publisher
    }

    /// Coalesces bursts of saves into one publish.
    public func setNeedsPublish() {
        pendingPublish?.cancel()
        pendingPublish = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            self?.publishNow()
        }
    }

    /// Applies queued widget actions, rebuilds the snapshot and writes it if it changed.
    /// Returns the current snapshot.
    @discardableResult
    public func publishNow() -> WidgetSnapshot {
        pendingPublish?.cancel()
        // Applying actions saves the context, which posts `didSave` → would schedule another publish.
        isPublishing = true
        defer { isPublishing = false }

        processPendingActions()
        let date = now()
        let snapshot = WidgetSnapshotBuilder.build(from: source.snapshotInput(now: date), now: date,
                                                   thumbnail: { [thumbnails] in thumbnails.thumbnail(for: $0) })
        if let current = store.load(), current.hasSameContent(as: snapshot) {
            return current
        }
        do {
            try store.save(snapshot)
            reloadTimelines()
        } catch {
            // Disk full / no App Group: the widgets keep their last state; the next save retries.
        }
        return snapshot
    }

    /// Drains the widget action queue into the store.
    func processPendingActions() {
        let actions = store.pendingActions()
        guard !actions.isEmpty else { return }
        let plan = WidgetPendingActionPlan(actions)
        let settled = source.completeFollowUps(plan.completions)
        try? store.removePendingActions(withIDs: plan.actionIDs(settledBy: settled))
    }

    private func observe() {
        let center = NotificationCenter.default
        let didSave = center.addObserver(forName: ModelContext.didSave, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.isPublishing else { return }
                self.setNeedsPublish()
            }
        }
        let didBecomeActive = center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil,
                                                 queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.setNeedsPublish() }
        }
        observers = [didSave, didBecomeActive]
    }
}
