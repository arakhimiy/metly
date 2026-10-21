import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureEvents

/// An event whose last day ends while the app stays open must end at that midnight — not at the next
/// launch / return to the foreground (until then it kept tagging new connections, kept the Home banner,
/// the event card as "card to share" and blocked Start Event on Free).
@MainActor
struct EventAutoEndTimingTests {
    @Test func nextAutoEndIsTheEarliestLastMidnightOfAnActiveEvent() throws {
        let context = try makeContext()
        insertEvent("Tech Week", in: context, start: date(2026, 9, 25), end: date(2026, 9, 28, 23, 59, 59))
        insertEvent("Product Meetup", in: context, start: date(2026, 9, 26), end: date(2026, 9, 26, 23, 59, 59))
        insertEvent("Old", in: context, start: date(2026, 9, 1), end: date(2026, 9, 1, 23, 59, 59), status: .ended)
        let events = try context.fetch(FetchDescriptor<Event>())

        #expect(EventLifecycle.nextAutoEnd(of: events, calendar: testCalendar) == date(2026, 9, 27))
    }

    @Test func nothingToWaitForWithoutActiveEvents() throws {
        let context = try makeContext()
        insertEvent("Old", in: context, start: date(2026, 9, 1), end: date(2026, 9, 1), status: .ended)
        insertEvent("Deleted", in: context, start: date(2026, 9, 26), end: date(2026, 9, 26)).markDeleted()
        let events = try context.fetch(FetchDescriptor<Event>())

        #expect(EventLifecycle.nextAutoEnd(of: events, calendar: testCalendar) == nil)
        #expect(EventLifecycle.nextAutoEnd(of: [], calendar: testCalendar) == nil)
    }

    @Test func eventEndsExactlyAtTheAutoEndMoment() throws {
        let context = try makeContext()
        let event = insertEvent("Product Meetup", in: context, start: date(2026, 9, 26), end: date(2026, 9, 26, 23, 59, 59))
        let moment = try #require(EventLifecycle.nextAutoEnd(of: [event], calendar: testCalendar))

        #expect(EventLifecycle.endExpiredEvents(in: context, now: moment.addingTimeInterval(-1), calendar: testCalendar).isEmpty)
        #expect(EventLifecycle.endExpiredEvents(in: context, now: moment, calendar: testCalendar) == [event.id])
        #expect(EventLifecycle.nextAutoEnd(of: [event], calendar: testCalendar) == nil)
    }

    @Test func resumedEventIsWaitedForAgain() throws {
        let context = try makeContext()
        let event = insertEvent("Product Meetup", in: context, start: date(2026, 9, 24), end: date(2026, 9, 25, 23, 59, 59),
                                status: .ended)
        EventLifecycle.resume(event, now: testNow, calendar: testCalendar)
        #expect(EventLifecycle.nextAutoEnd(of: [event], calendar: testCalendar) == date(2026, 9, 27))
    }
}

/// EVENT_DETAIL's status pill uses calendar days like Home and FOLLOWUPS (SPEC §2.5.14: red overdue,
/// tint today): a reminder due earlier today is "Today", not "Overdue".
@MainActor
struct FollowUpStatusDayTests {
    private func person(dueAt: Date, in context: ModelContext) -> Connection {
        let person = insertPerson("Kamila Yusupova", in: context)
        let followUp = FollowUp(title: "Follow up", channel: .telegram, dueAt: dueAt)
        context.insert(followUp)
        followUp.connection = person
        return person
    }

    @Test func dueEarlierTodayIsToday() throws {
        let context = try makeContext()
        let due = date(2026, 9, 26, 10, 0)   // testNow is 14:32 the same day
        let status = FollowUpStatus(person: person(dueAt: due, in: context), now: testNow, calendar: testCalendar)

        #expect(status == .due(due))
        #expect(status.title(now: testNow, calendar: testCalendar) == "Today")
    }

    @Test func dueYesterdayIsOverdue() throws {
        let context = try makeContext()
        let due = date(2026, 9, 25, 23, 59)
        let status = FollowUpStatus(person: person(dueAt: due, in: context), now: testNow, calendar: testCalendar)
        #expect(status == .overdue(due))
    }

    @Test func dueLaterTodayIsToday() throws {
        let context = try makeContext()
        let due = date(2026, 9, 26, 18, 0)
        let status = FollowUpStatus(person: person(dueAt: due, in: context), now: testNow, calendar: testCalendar)
        #expect(status == .due(due))
    }
}
