import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureEvents

@MainActor
struct EventStatsTests {
    // MARK: Membership

    @Test func membersAreLinkedOrStampedWithTheEvent() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let linked = insertPerson("Linked", at: event, in: context)
        let stampedOnly = Connection(fullName: "Stamped", source: .webShareBack,
                                     context: MeetingContext(eventID: event.id, eventName: event.name, metAt: testNow))
        context.insert(stampedOnly)
        let byName = Connection(fullName: "By Name", source: .manual,
                                context: MeetingContext(eventName: " TASHKENT tech week ", metAt: testNow))
        context.insert(byName)
        insertPerson("Elsewhere", in: context)

        let other = insertEvent("Tashkent Tech Week", in: context, status: .ended)
        let otherPerson = insertPerson("Other Event, Same Name", at: other, in: context)

        let names = Set(EventMembership.members(of: event, in: context).map(\.fullName))
        #expect(names == ["Linked", "Stamped", "By Name"])
        #expect(!EventMembership.isMember(otherPerson, of: event))
        #expect(EventMembership.isMember(linked, of: event))
    }

    @Test func removedAndBlockedPeopleAreNotMembers() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        insertPerson("Kept", at: event, in: context)
        insertPerson("Removed", at: event, in: context).markDeleted()
        insertPerson("Blocked", at: event, in: context).isBlocked = true

        let people = try context.fetch(FetchDescriptor<Connection>())
        #expect(EventMembership.members(of: event, among: people).map(\.fullName) == ["Kept"])
    }

    @Test func membersAreSortedByMostRecentMeeting() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        insertPerson("Morning", at: event, in: context, metAt: date(2026, 9, 26, 9))
        insertPerson("Afternoon", at: event, in: context, metAt: date(2026, 9, 26, 14))
        insertPerson("Yesterday", at: event, in: context, metAt: date(2026, 9, 25, 18))
        #expect(EventMembership.members(of: event, in: context).map(\.fullName) == ["Afternoon", "Morning", "Yesterday"])
    }

    // MARK: Stats

    @Test func statsCountPeopleNotesAndOpenFollowUps() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let kamila = insertPerson("Kamila", at: event, in: context, note: "Pitch deck")
        insertFollowUp(for: kamila, in: context)
        let sardor = insertPerson("Sardor", at: event, in: context, note: "   ")
        insertFollowUp(for: sardor, in: context, done: true)
        let dilnoza = insertPerson("Dilnoza", at: event, in: context, note: "Portfolio")
        insertFollowUp(for: dilnoza, in: context).markDeleted()
        insertPerson("Elsewhere", in: context, note: "Not counted")

        let stats = EventStats(members: EventMembership.members(of: event, in: context))
        #expect(stats == EventStats(people: 3, withNotes: 2, openFollowUps: 1, withoutFollowUp: 2))
        #expect(EventMembership.withoutNotes(EventMembership.members(of: event, in: context)).map(\.fullName) == ["Sardor"])
    }

    @Test func emptyEventHasZeroStats() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        #expect(EventStats(members: EventMembership.members(of: event, in: context)) == EventStats())
    }

    @Test func summaryCopyMatchesTheSpec() {
        #expect(EventCopy.summary(EventStats(people: 6, withNotes: 2, openFollowUps: 4, withoutFollowUp: 2))
                == "You met 6 people. 2 have notes. 4 follow-ups are scheduled.")
        #expect(EventCopy.summary(EventStats(people: 1, withNotes: 1, openFollowUps: 1, withoutFollowUp: 0))
                == "You met 1 person. 1 has a note. 1 follow-up is scheduled.")
        #expect(EventCopy.summary(EventStats()) == "You didn’t add anyone at this event.")
        #expect(EventCopy.remindersSet(1) == "1 reminder set for tomorrow")
        #expect(EventCopy.remindersSet(4) == "4 reminders set for tomorrow")
    }

    // MARK: Status pill

    @Test func followUpStatusReflectsTheOpenReminder() throws {
        let context = try makeContext()
        let overdue = insertPerson("Overdue", in: context)
        insertFollowUp(for: overdue, in: context, dueInDays: -1)
        let upcoming = insertPerson("Upcoming", in: context)
        insertFollowUp(for: upcoming, in: context, dueInDays: 1)
        let done = insertPerson("Done", in: context)
        insertFollowUp(for: done, in: context, done: true)
        let none = insertPerson("None", in: context)

        #expect(FollowUpStatus(person: overdue, now: testNow).title(now: testNow, calendar: testCalendar) == "Overdue")
        #expect(FollowUpStatus(person: upcoming, now: testNow).title(now: testNow, calendar: testCalendar) == "Tomorrow")
        #expect(FollowUpStatus(person: done, now: testNow) == .done)
        #expect(FollowUpStatus(person: none, now: testNow) == .none)
    }
}
