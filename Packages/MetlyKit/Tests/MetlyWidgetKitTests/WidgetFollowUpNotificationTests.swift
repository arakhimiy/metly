import Foundation
import Testing
@testable import MetlyWidgetKit

/// Records what a widget "Done" tap asked UserNotifications to withdraw.
final class RecordingNotificationCenter: WidgetNotificationCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers: [String] = []

    var removed: [String] { lock.withLock { identifiers } }

    func removeNotifications(withIdentifiers identifiers: [String]) {
        lock.withLock { self.identifiers += identifiers }
    }
}

@Suite("Widget Done and the reminder's local notification")
struct WidgetFollowUpNotificationTests {
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    /// Must stay identical to FeatureHome's `FollowUpNotificationPayload.identifier(for:)`
    /// (pinned to the same literal in FeatureHomeTests `identifierRoundTrips`).
    @Test("The identifier matches the app scheduler's scheme")
    func identifierScheme() {
        #expect(WidgetFollowUpNotification.identifier(for: id) == "followup.11111111-2222-3333-4444-555555555555")
    }

    @Test("A Done tap withdraws the pending and delivered notification right away")
    func doneTapCancelsNotification() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        try store.save(WidgetSnapshot.sample(now: testNow, calendar: testCalendar))
        let center = RecordingNotificationCenter()

        try store.enqueueFollowUpCompletion(id, at: testNow, notifications: center)

        #expect(center.removed == ["followup.11111111-2222-3333-4444-555555555555"])
        #expect(store.pendingActions().map(\.targetID) == [id])
    }

    @Test("A Done tap before anything was published still withdraws the notification")
    func doneTapWithoutSnapshotCancelsNotification() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let center = RecordingNotificationCenter()

        try store.enqueueFollowUpCompletion(id, notifications: center)

        #expect(center.removed == [WidgetFollowUpNotification.identifier(for: id)])
    }

    @Test("Queued completions are reported so the app doesn't reschedule their notifications")
    func pendingCompletionIDs() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let other = UUID()
        #expect(store.pendingFollowUpCompletionIDs().isEmpty)

        try store.enqueueFollowUpCompletion(id, notifications: RecordingNotificationCenter())
        try store.enqueueFollowUpCompletion(other, notifications: RecordingNotificationCenter())
        try store.enqueueFollowUpCompletion(id, notifications: RecordingNotificationCenter())   // double tap

        #expect(store.pendingFollowUpCompletionIDs() == [id, other])

        let settled = Set(store.pendingActions().filter { $0.targetID == id }.map(\.id))
        try store.removePendingActions(withIDs: settled)
        #expect(store.pendingFollowUpCompletionIDs() == [other])
    }
}
