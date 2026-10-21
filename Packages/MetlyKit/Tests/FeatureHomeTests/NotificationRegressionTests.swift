import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
import UserNotifications
@testable import FeatureHome

/// Time-zone changes must re-add pending requests: the trigger is wall-clock time in the zone it was
/// scheduled in, so without a reschedule a 10:00 Tashkent reminder fires at 10:00 Berlin after the flight.
struct NotificationTimeZoneTests {
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
    private let tashkent = TimeZone(identifier: "Asia/Tashkent")!
    private let berlin = TimeZone(identifier: "Europe/Berlin")!

    private func payload(in zone: TimeZone) -> FollowUpNotificationPayload {
        FollowUpNotificationPayload(followUpID: id, personName: "Kamila", what: "Send the deck", channel: .telegram,
                                    hasChannelValue: true, dueAt: date(2026, 9, 27, 10, 0), timeZone: zone)
    }

    @Test func requestScheduledInAnotherZoneIsReAdded() {
        let scheduledInTashkent = payload(in: tashkent)
        let desiredInBerlin = payload(in: berlin)

        #expect(scheduledInTashkent.fingerprint != desiredInBerlin.fingerprint)
        let toAdd = FollowUpNotificationPlanner.payloadsToAdd(
            desired: [desiredInBerlin],
            pendingFingerprints: [scheduledInTashkent.identifier: scheduledInTashkent.fingerprint]
        )
        #expect(toAdd == [desiredInBerlin])
    }

    @Test func unchangedZoneKeepsThePendingRequest() {
        let scheduled = payload(in: berlin)
        #expect(FollowUpNotificationPlanner.payloadsToAdd(desired: [payload(in: berlin)],
                                                          pendingFingerprints: [scheduled.identifier: scheduled.fingerprint]).isEmpty)
    }

    @Test func plannerBuildsPayloadsForTheGivenZone() {
        let candidate = FollowUpNotificationPlanner.Candidate(id: id, personName: "Kamila", what: "Send the deck",
                                                              channel: .telegram, hasChannelValue: true,
                                                              dueAt: date(2026, 9, 27, 10, 0), isOpen: true)
        let payloads = FollowUpNotificationPlanner.payloads(for: [candidate], now: testNow, enabled: true, timeZone: berlin)
        #expect(payloads.first?.fingerprint == payload(in: berlin).fingerprint)
        #expect(payloads.first?.fingerprint != payload(in: tashkent).fingerprint)
    }

    @Test func reAddedRequestFiresAtTheDueMomentInTheNewZone() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        let trigger = try #require(payload(in: berlin).makeRequest(calendar: calendar).trigger as? UNCalendarNotificationTrigger)
        // 10:00 in Tashkent (UTC+5) is 07:00 in Berlin (CEST, UTC+2).
        #expect(trigger.dateComponents.day == 27)
        #expect(trigger.dateComponents.hour == 7)
    }
}

/// A widget "Done" tap is applied to the store only when the app next runs. Until then the scheduler
/// must not (re)schedule that reminder — the widget already withdrew its notification.
@MainActor
struct NotificationWidgetDoneTests {
    @Test func reminderDoneOnTheWidgetGetsNoNotification() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila Yusupova", in: context, telegram: "kamila")
        let doneOnWidget = insertReminder(for: person, in: context, dueAt: date(2026, 9, 27))
        let stillOpen = insertReminder(for: person, in: context, dueAt: date(2026, 9, 28))

        let candidates = [doneOnWidget, stillOpen].compactMap {
            FollowUpNotificationScheduler.candidate($0, doneElsewhere: [doneOnWidget.id])
        }
        let payloads = FollowUpNotificationPlanner.payloads(for: candidates, now: testNow, enabled: true)

        #expect(payloads.map(\.followUpID) == [stillOpen.id])
        // Not "open" either, so an already-delivered notification for it is removed as well.
        #expect(candidates.filter(\.isOpen).map(\.id) == [stillOpen.id])
    }

    @Test func withoutPendingWidgetTapsEveryOpenReminderIsScheduled() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila Yusupova", in: context, telegram: "kamila")
        let first = insertReminder(for: person, in: context, dueAt: date(2026, 9, 27))
        let second = insertReminder(for: person, in: context, dueAt: date(2026, 9, 28))

        let candidates = [first, second].compactMap { FollowUpNotificationScheduler.candidate($0) }
        let payloads = FollowUpNotificationPlanner.payloads(for: candidates, now: testNow, enabled: true)
        #expect(payloads.map(\.followUpID) == [first.id, second.id])
    }
}

/// Stand-in for a reschedule pass that can be held mid-flight (as a real pass is while it awaits
/// `UNUserNotificationCenter`).
@MainActor
final class PassProbe {
    /// What the "store" says; each pass records the value it read when it started.
    var version = 0
    private(set) var started = 0
    private(set) var completed: [Int] = []
    private var isGateClosed = true
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func pass() async {
        let seen = version
        started += 1
        if isGateClosed {
            await withCheckedContinuation { waiters.append($0) }
        }
        completed.append(seen)
    }

    func openGate() {
        isGateClosed = false
        waiters.forEach { $0.resume() }
        waiters.removeAll()
    }
}

@MainActor
struct SerialPassRunnerTests {
    /// "Snooze 1 Day" saves, then awaits `reschedule()` before the notification delegate returns and iOS
    /// may suspend the app. When a pass that read the store before the snooze is still running, the call
    /// has to wait for the follow-up pass; returning early leaves the snoozed reminder without a notification.
    @Test func runReturnsOnlyAfterAPassThatSawTheRequest() async {
        let probe = PassProbe()
        let runner = SerialPassRunner { await probe.pass() }
        let first = Task { await runner.run() }
        while probe.started < 1 { await Task.yield() }

        probe.version = 1   // the snooze saved a new due date while pass 1 is in flight
        let second = Task { () -> [Int] in
            await runner.run()
            return probe.completed
        }
        probe.openGate()
        let completedWhenSecondReturned = await second.value
        await first.value

        #expect(completedWhenSecondReturned.contains(1))
        #expect(probe.completed == [0, 1])
    }

    @Test func overlappingCallsAreFoldedIntoOneMorePass() async {
        let probe = PassProbe()
        let runner = SerialPassRunner { await probe.pass() }
        let first = Task { await runner.run() }
        while probe.started < 1 { await Task.yield() }

        probe.version = 1
        let others = (0..<3).map { _ in Task { await runner.run() } }
        probe.openGate()
        await first.value
        for task in others { await task.value }

        #expect(probe.completed == [0, 1])
    }

    @Test func idleRunnerStartsANewPass() async {
        let probe = PassProbe()
        probe.openGate()
        let runner = SerialPassRunner { await probe.pass() }
        await runner.run()
        probe.version = 1
        await runner.run()
        #expect(probe.completed == [0, 1])
    }
}

/// Home / FOLLOWUPS re-render at local midnight so "Today" / "Overdue" don't go stale.
struct DayRolloverTests {
    @Test func nextDayStartsAtLocalMidnight() {
        #expect(FollowUpDates.startOfNextDay(after: testNow, calendar: testCalendar) == date(2026, 9, 27, 0, 0))
        #expect(FollowUpDates.startOfNextDay(after: date(2026, 9, 26, 0, 0), calendar: testCalendar) == date(2026, 9, 27, 0, 0))
    }

    /// Europe/Berlin falls back on Sun, Oct 25, 2026 (a 25-hour day): roll over at midnight, not at 23:00.
    @Test func longDstDayRollsOverAtMidnight() {
        let noon = date(2026, 10, 25, 12, 0, calendar: berlinCalendar)
        #expect(FollowUpDates.startOfNextDay(after: noon, calendar: berlinCalendar)
                == date(2026, 10, 26, 0, 0, calendar: berlinCalendar))
    }

    /// Spring forward (Sun, Mar 29, 2026, 23 hours).
    @Test func shortDstDayRollsOverAtMidnight() {
        let noon = date(2026, 3, 29, 12, 0, calendar: berlinCalendar)
        #expect(FollowUpDates.startOfNextDay(after: noon, calendar: berlinCalendar)
                == date(2026, 3, 30, 0, 0, calendar: berlinCalendar))
    }
}
