import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureEvents

@MainActor
struct EventFollowUpPlannerTests {
    @Test func createsATomorrowReminderForEveryoneWithoutOne() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let telegram = insertPerson("Telegram", at: event, in: context, telegram: "@t", email: "t@x.uz")
        let email = insertPerson("Email", at: event, in: context, email: "e@x.uz", phone: "+998 71 200 00 00")
        let phone = insertPerson("Phone", at: event, in: context, phone: "+998 71 200 00 01")
        let covered = insertPerson("Covered", at: event, in: context)
        let existing = insertFollowUp(for: covered, in: context, dueInDays: 5)

        let members = EventMembership.members(of: event, in: context)
        let outcome = EventFollowUpPlanner.followUpWithEveryone(eventName: event.name, members: members, in: context,
                                                                limits: .pro, now: testNow, calendar: testCalendar)

        #expect(outcome == EventFollowUpOutcome(scheduled: 3, skipped: 0, openCountAfter: 4))
        #expect(!outcome.hitLimit)
        for person in [telegram, email, phone] {
            let reminder = try #require(person.openFollowUp)
            #expect(reminder.title == "Follow up from Tashkent Tech Week")
            #expect(reminder.dueAt == date(2026, 9, 27, 10, 0))
        }
        #expect(telegram.openFollowUp?.channel == .telegram)
        #expect(email.openFollowUp?.channel == .email)
        #expect(phone.openFollowUp?.channel == .call)
        // The person who already had a reminder keeps it untouched.
        #expect(covered.followUps.count == 1)
        #expect(covered.openFollowUp?.id == existing.id)
    }

    @Test func freePlanSchedulesOnlyUpToTheLimit() throws {
        let context = try makeContext()
        // Three open reminders elsewhere → room for two more on Free (limit 5).
        for index in 0..<3 {
            insertFollowUp(for: insertPerson("Elsewhere \(index)", in: context), in: context)
        }
        let event = insertEvent(in: context)
        for index in 0..<4 {
            insertPerson("Guest \(index)", at: event, in: context, metAt: date(2026, 9, 26, 10 + index))
        }

        let members = EventMembership.members(of: event, in: context)
        let outcome = EventFollowUpPlanner.followUpWithEveryone(eventName: event.name, members: members, in: context,
                                                                limits: .free, now: testNow, calendar: testCalendar)

        #expect(outcome == EventFollowUpOutcome(scheduled: 2, skipped: 2, openCountAfter: 5))
        #expect(outcome.hitLimit)
        #expect(FollowUpPolicy.openCount(in: context) == 5)
        // List order (most recently met first) decides who gets the remaining slots.
        #expect(members.prefix(2).allSatisfy { $0.openFollowUp != nil })
        #expect(members.suffix(2).allSatisfy { $0.openFollowUp == nil })
    }

    @Test func freePlanAtTheLimitSchedulesNothing() throws {
        let context = try makeContext()
        for index in 0..<5 {
            insertFollowUp(for: insertPerson("Elsewhere \(index)", in: context), in: context)
        }
        let event = insertEvent(in: context)
        insertPerson("Guest", at: event, in: context)

        let outcome = EventFollowUpPlanner.followUpWithEveryone(
            eventName: event.name, members: EventMembership.members(of: event, in: context), in: context,
            limits: .free, now: testNow, calendar: testCalendar)

        #expect(outcome == EventFollowUpOutcome(scheduled: 0, skipped: 1, openCountAfter: 5))
    }

    @Test func doneRemindersDoNotCountAsOpen() throws {
        let context = try makeContext()
        let event = insertEvent(in: context)
        let person = insertPerson("Followed Up Before", at: event, in: context)
        insertFollowUp(for: person, in: context, done: true)

        #expect(EventFollowUpPlanner.candidates(among: [person]).count == 1)
        let outcome = EventFollowUpPlanner.followUpWithEveryone(eventName: event.name, members: [person], in: context,
                                                                limits: .free, now: testNow, calendar: testCalendar)
        #expect(outcome.scheduled == 1)
    }

    @Test func remainingCapacity() {
        #expect(EventFollowUpPlanner.remainingCapacity(openCount: 3, limits: .free) == 2)
        #expect(EventFollowUpPlanner.remainingCapacity(openCount: 7, limits: .free) == 0)
        #expect(EventFollowUpPlanner.remainingCapacity(openCount: 7, limits: .pro) == nil)
    }
}
