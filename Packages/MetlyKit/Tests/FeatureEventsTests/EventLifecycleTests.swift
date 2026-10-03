import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureEvents

@MainActor
struct EventLifecycleTests {
    // MARK: Auto-end

    @Test func endsEventsWhoseLastDayIsOver() throws {
        let context = try makeContext()
        let expired = insertEvent("Yesterday's Meetup", in: context, start: date(2026, 9, 24), end: date(2026, 9, 25, 23, 59, 59))
        let running = insertEvent("Tech Week", in: context, start: date(2026, 9, 25), end: date(2026, 9, 26, 23, 59, 59))

        let ended = EventLifecycle.endExpiredEvents(in: context, now: testNow, calendar: testCalendar)

        #expect(ended == [expired.id])
        #expect(expired.status == .ended)
        #expect(expired.syncState == .pendingUpsert)
        // Ended when its last day was over, not when the app happened to open.
        #expect(expired.endedAt == date(2026, 9, 26))
        #expect(running.isActive)
        #expect(running.endedAt == nil)
    }

    @Test func eventEndingTodayIsNotExpiredUntilMidnight() throws {
        let context = try makeContext()
        // Stored as a plain day (start of day) — still runs for the whole of that day.
        let event = insertEvent(in: context, start: date(2026, 9, 26), end: date(2026, 9, 26))
        #expect(!EventLifecycle.isExpired(event, now: testNow, calendar: testCalendar))
        #expect(!EventLifecycle.isExpired(event, now: date(2026, 9, 26, 23, 59, 59), calendar: testCalendar))
        #expect(EventLifecycle.isExpired(event, now: date(2026, 9, 27), calendar: testCalendar))
    }

    @Test func ignoresEndedAndDeletedEvents() throws {
        let context = try makeContext()
        let ended = insertEvent("Old", in: context, start: date(2026, 9, 1), end: date(2026, 9, 2), status: .ended)
        ended.endedAt = date(2026, 9, 2, 18)
        let deleted = insertEvent("Deleted", in: context, start: date(2026, 9, 1), end: date(2026, 9, 2))
        deleted.markDeleted()

        #expect(EventLifecycle.endExpiredEvents(in: context, now: testNow, calendar: testCalendar).isEmpty)
        #expect(ended.endedAt == date(2026, 9, 2, 18))
        #expect(deleted.status == .active)
    }

    @Test func returnsEveryExpiredEvent() throws {
        let context = try makeContext()
        let first = insertEvent("First", in: context, start: date(2026, 9, 1), end: date(2026, 9, 2))
        let second = insertEvent("Second", in: context, start: date(2026, 9, 10), end: date(2026, 9, 12))
        let ended = EventLifecycle.endExpiredEvents(in: context, now: testNow, calendar: testCalendar)
        #expect(Set(ended) == [first.id, second.id])
        #expect(try context.fetch(Event.active).isEmpty)
    }

    // MARK: Limits

    @Test func freePlanAllowsOneActiveEvent() throws {
        let context = try makeContext()
        #expect(EventLifecycle.canActivate(in: context, limits: .free))
        let active = insertEvent(in: context)
        #expect(!EventLifecycle.canActivate(in: context, limits: .free))
        #expect(EventLifecycle.canActivate(in: context, limits: .pro))
        // Resuming the active event itself is not a second one.
        #expect(EventLifecycle.canActivate(in: context, limits: .free, excluding: active.id))
    }

    @Test func endedEventsDoNotCountTowardsTheLimit() throws {
        let context = try makeContext()
        insertEvent(in: context, status: .ended)
        #expect(EventLifecycle.canActivate(in: context, limits: .free))
    }

    // MARK: End / resume

    @Test func endingSetsStatusAndTimestamp() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        EventLifecycle.end(event, at: testNow)
        #expect(event.status == .ended)
        #expect(event.endedAt == testNow)
        #expect(context.activeEvent() == nil)
    }

    @Test func resumingAnExpiredEventRunsUntilTheEndOfToday() throws {
        let context = try makeContext()
        let event = insertEvent(in: context, start: date(2026, 9, 20), end: date(2026, 9, 22, 23, 59, 59), status: .ended)
        event.endedAt = date(2026, 9, 23)

        EventLifecycle.resume(event, now: testNow, calendar: testCalendar)

        #expect(event.isActive)
        #expect(event.endedAt == nil)
        #expect(event.endDate == date(2026, 9, 26, 23, 59, 59))
        #expect(EventLifecycle.endExpiredEvents(in: context, now: testNow, calendar: testCalendar).isEmpty)
    }

    @Test func resumingKeepsAFutureEndDate() throws {
        let context = try makeContext()
        let event = insertEvent(in: context, start: date(2026, 9, 25), end: date(2026, 9, 28, 23, 59, 59), status: .ended)
        EventLifecycle.resume(event, now: testNow, calendar: testCalendar)
        #expect(event.endDate == date(2026, 9, 28, 23, 59, 59))
    }

    // MARK: Edit cascade

    @Test func renameCascadesToTheEventsConnections() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let kamila = insertPerson("Kamila", at: event, in: context)
        let elsewhere = insertPerson("Timur", in: context)
        elsewhere.context.place = "IT Park"
        let earlier = insertPerson("Sardor", in: context)
        earlier.previousMeetings = [MeetingContext(eventID: event.id, eventName: event.name, metAt: date(2026, 9, 25))]

        var draft = EventDraft(event: event, calendar: testCalendar)
        draft.name = "Tashkent Tech Week 2026"
        draft.place = "Hilton"
        EventLifecycle.update(event, with: draft, in: context, calendar: testCalendar)

        #expect(event.name == "Tashkent Tech Week 2026")
        #expect(kamila.context.eventName == "Tashkent Tech Week 2026")
        #expect(kamila.context.place == "Hilton")
        #expect(kamila.context.city == "Tashkent")
        #expect(kamila.syncState == .pendingUpsert)
        #expect(elsewhere.context.eventName == nil)
        #expect(elsewhere.context.place == "IT Park")
        #expect(earlier.previousMeetings.first?.eventName == "Tashkent Tech Week 2026")
    }

    @Test func renameKeepsAPlaceTheUserChanged() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let person = insertPerson("Kamila", at: event, in: context)
        person.context.place = "Coffee corner"

        var draft = EventDraft(event: event, calendar: testCalendar)
        draft.place = "Hilton"
        EventLifecycle.update(event, with: draft, in: context, calendar: testCalendar)

        #expect(person.context.place == "Coffee corner")
    }

    @Test func renameAdoptsPeopleKnownOnlyByEventName() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let legacy = Connection(fullName: "Legacy", source: .manual,
                                context: MeetingContext(eventName: "tashkent tech week", metAt: testNow))
        context.insert(legacy)

        var draft = EventDraft(event: event, calendar: testCalendar)
        draft.name = "TTW"
        EventLifecycle.update(event, with: draft, in: context, calendar: testCalendar)

        #expect(legacy.context.eventName == "TTW")
        #expect(legacy.context.eventID == event.id)
        #expect(legacy.event?.id == event.id)
    }
}
