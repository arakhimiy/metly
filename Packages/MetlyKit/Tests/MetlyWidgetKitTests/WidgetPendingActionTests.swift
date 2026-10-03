import Foundation
import MetlyCore
import Testing
@testable import MetlyWidgetKit

@Suite("Pending widget actions")
struct WidgetPendingActionTests {
    let first = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    let second = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    @Test("The plan has one completion per follow-up; the first tap's time wins")
    func planDeduplicates() {
        let later = WidgetPendingAction.completeFollowUp(first, at: testNow.addingTimeInterval(30))
        let earlier = WidgetPendingAction.completeFollowUp(first, at: testNow)
        let other = WidgetPendingAction.completeFollowUp(second, at: testNow.addingTimeInterval(10))
        let plan = WidgetPendingActionPlan([later, other, earlier])

        #expect(plan.completions == [
            WidgetFollowUpCompletion(followUpID: first, completedAt: testNow),
            WidgetFollowUpCompletion(followUpID: second, completedAt: testNow.addingTimeInterval(10)),
        ])
        #expect(plan.actionIDs(settledBy: [first]) == [later.id, earlier.id])
        #expect(plan.actionIDs(settledBy: []) == [])
    }

    @Test("Overlaying a completion hides the row and its due date")
    func overlayHidesCompletedRow() throws {
        let snapshot = WidgetSnapshot.sample(now: testNow, calendar: testCalendar)
        let done = try #require(snapshot.followUps.first)
        let overlaid = snapshot.applying([.completeFollowUp(done.id)])

        #expect(!overlaid.followUps.contains { $0.id == done.id })
        #expect(overlaid.followUps.count == snapshot.followUps.count - 1)
        #expect(overlaid.openFollowUpCount == snapshot.openFollowUpCount - 1)
        #expect(overlaid.dueFollowUpCount(at: testNow, calendar: testCalendar) == snapshot.dueFollowUpCount(at: testNow, calendar: testCalendar) - 1)
        #expect(snapshot.applying([]) == snapshot)
    }

    @Test("Removing settled entries keeps actions queued meanwhile")
    func queueRemovesOnlySettledEntries() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let a = WidgetPendingAction.completeFollowUp(first)
        let b = WidgetPendingAction.completeFollowUp(second)
        try store.enqueue(a)
        try store.enqueue(b)
        #expect(store.pendingActions().map(\.id) == [a.id, b.id])

        try store.removePendingActions(withIDs: [a.id])
        #expect(store.pendingActions().map(\.id) == [b.id])
    }

    @Test("A widget Done tap queues the completion and updates the snapshot optimistically")
    func doneTapUpdatesSnapshot() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let snapshot = WidgetSnapshot.sample(now: testNow, calendar: testCalendar)
        try store.save(snapshot)
        let row = try #require(snapshot.followUps.first)

        try store.enqueueFollowUpCompletion(row.id, at: testNow)

        #expect(store.pendingActions().map(\.targetID) == [row.id])
        #expect(store.load()?.followUps.contains { $0.id == row.id } == false)
        #expect(store.load()?.openFollowUpCount == snapshot.openFollowUpCount - 1)
    }

    @Test("A Done tap before anything was published only queues")
    func doneTapWithoutSnapshot() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        try store.enqueueFollowUpCompletion(first)
        #expect(store.pendingActions().count == 1)
        #expect(store.load() == nil)
    }
}

// MARK: - Publisher

@MainActor
final class FakeWidgetSource: WidgetSnapshotSource {
    var input: WidgetSnapshotInput?
    /// Follow-ups the "store" can't settle yet (e.g. save failed) — they stay queued.
    var unsettled: Set<UUID> = []
    private(set) var received: [[WidgetFollowUpCompletion]] = []

    init(input: WidgetSnapshotInput?) {
        self.input = input
    }

    func snapshotInput(now: Date) -> WidgetSnapshotInput? { input }

    func completeFollowUps(_ completions: [WidgetFollowUpCompletion]) -> Set<UUID> {
        received.append(completions)
        // Apply: drop completed follow-ups from the input, like marking them done in SwiftData.
        let applied = Set(completions.map(\.followUpID)).subtracting(unsettled)
        input?.openFollowUps.removeAll { applied.contains($0.id) }
        return applied
    }
}

@MainActor
@Suite("Snapshot publisher")
struct WidgetSnapshotPublisherTests {
    @Test("Publishing writes the snapshot and reloads widgets only when content changed")
    func reloadsOnlyOnChange() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let source = FakeWidgetSource(input: makeInput(followUps: [followUp(1, due: testNow)]))
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(source: source, store: store, now: { testNow }, reloadTimelines: { reloads += 1 })

        let published = publisher.publishNow()
        #expect(reloads == 1)
        #expect(store.load()?.hasSameContent(as: published) == true)

        publisher.publishNow()
        #expect(reloads == 1)   // nothing changed

        source.input?.activeEventName = "Product Meetup"
        publisher.publishNow()
        #expect(reloads == 2)
        #expect(store.load()?.activeEventName == "Product Meetup")
    }

    @Test("Queued Done taps are applied before building; settled entries leave the queue")
    func appliesPendingActions() throws {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let rows = [followUp(1, due: testNow), followUp(2, due: testNow), followUp(3, due: testNow)]
        let source = FakeWidgetSource(input: makeInput(followUps: rows))
        source.unsettled = [rows[1].id]
        let publisher = WidgetSnapshotPublisher(source: source, store: store, now: { testNow }, reloadTimelines: {})

        try store.enqueueFollowUpCompletion(rows[0].id, at: testNow)
        try store.enqueueFollowUpCompletion(rows[0].id, at: testNow.addingTimeInterval(5))   // double tap
        try store.enqueueFollowUpCompletion(rows[1].id, at: testNow)

        let snapshot = publisher.publishNow()

        #expect(source.received == [[
            WidgetFollowUpCompletion(followUpID: rows[0].id, completedAt: testNow),
            WidgetFollowUpCompletion(followUpID: rows[1].id, completedAt: testNow),
        ]])
        #expect(snapshot.followUps.map(\.id) == [rows[1].id, rows[2].id])
        #expect(store.pendingActions().map(\.targetID) == [rows[1].id])   // retried next time
    }

    @Test("Signing out publishes an empty snapshot")
    func signedOutPublishesEmpty() {
        let store = makeTemporaryStore()
        defer { store.removeAll() }
        let source = FakeWidgetSource(input: makeInput())
        let publisher = WidgetSnapshotPublisher(source: source, store: store, now: { testNow }, reloadTimelines: {})
        publisher.publishNow()
        #expect(store.load()?.isSignedIn == true)

        source.input = nil
        publisher.publishNow()
        #expect(store.load()?.isSignedIn == false)
        #expect(store.load()?.cards.isEmpty == true)
    }
}
