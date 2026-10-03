import Foundation
import MetlyWidgetKit
import WidgetKit

nonisolated struct FollowUpsWidgetEntry: TimelineEntry {
    let date: Date
    let content: FollowUpsWidgetContent

    static var placeholder: FollowUpsWidgetEntry {
        FollowUpsWidgetEntry(date: .now, content: FollowUpsWidgetContent.resolve(snapshot: .sample(), at: .now))
    }
}

/// Timeline for the Follow-ups widget. Pending "Done" taps the app hasn't applied yet are overlaid,
/// so a tapped row disappears immediately. Entries at midnight roll "due today" over without the app.
nonisolated struct FollowUpsTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> FollowUpsWidgetEntry {
        .placeholder
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (FollowUpsWidgetEntry) -> Void) {
        let store = WidgetSnapshotStore.appGroup
        let stored = store.load()
        let snapshot = context.isPreview && stored?.isSignedIn != true ? .sample() : stored
        completion(FollowUpsWidgetEntry(date: .now, content: FollowUpsWidgetContent.resolve(
            snapshot: snapshot, pending: store.pendingActions(), at: .now)))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<FollowUpsWidgetEntry>) -> Void) {
        let store = WidgetSnapshotStore.appGroup
        let snapshot = store.load()
        let pending = store.pendingActions()
        let entries = WidgetTimelineSchedule.entryDates(from: .now).map { date in
            FollowUpsWidgetEntry(date: date, content: FollowUpsWidgetContent.resolve(snapshot: snapshot, pending: pending, at: date))
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}
