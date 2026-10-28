import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import MetlyCapture

@MainActor
struct CaptureApplyTests {

    // MARK: Follow-up limit

    @Test func freePlanBlocksTheSixthOpenFollowUp() throws {
        let context = try makeContext()
        for index in 0..<5 {
            insertOpenFollowUp(for: insertPerson("Person \(index)", in: context), in: context)
        }
        let newcomer = insertPerson("Newcomer", in: context)

        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.followUp = FollowUpDraft(pick: .tomorrow, channel: .telegram, now: testNow, calendar: testCalendar)
        let result = draft.apply(to: newcomer, in: context, limits: .free, now: testNow, calendar: testCalendar)

        #expect(result.followUp == .limitReached(openCount: 5))
        #expect(result.hitFollowUpLimit)
        #expect(!result.reminderSet)
        #expect(newcomer.followUps.isEmpty)
        #expect(FollowUpPolicy.openCount(in: context) == 5)
    }

    @Test func blockedFollowUpStillSavesTheNote() throws {
        let context = try makeContext()
        for index in 0..<5 {
            insertOpenFollowUp(for: insertPerson("Person \(index)", in: context), in: context)
        }
        let newcomer = insertPerson("Newcomer", in: context)
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow), note: "Loves design systems")
        draft.followUp = FollowUpDraft(pick: .tomorrow, channel: .telegram, now: testNow, calendar: testCalendar)
        draft.apply(to: newcomer, in: context, limits: .free, now: testNow, calendar: testCalendar)
        #expect(newcomer.note == "Loves design systems")
    }

    @Test func proPlanIsUnlimited() throws {
        let context = try makeContext()
        for index in 0..<5 {
            insertOpenFollowUp(for: insertPerson("Person \(index)", in: context), in: context)
        }
        let newcomer = insertPerson("Newcomer", in: context)
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.followUp = FollowUpDraft(pick: .nextWeek, channel: .email, now: testNow, calendar: testCalendar)
        let result = draft.apply(to: newcomer, in: context, limits: .pro, now: testNow, calendar: testCalendar)

        guard case .scheduled = result.followUp else {
            Issue.record("Expected a scheduled reminder, got \(result.followUp)")
            return
        }
        #expect(newcomer.followUps.count == 1)
        #expect(newcomer.followUps.first?.title == MetlyCapture.defaultFollowUpTitle)
        #expect(newcomer.followUps.first?.channel == .email)
        #expect(result.toastMessage(otherwise: "Context Saved") == "Saved · Reminder Set")
    }

    @Test func doneAndRemovedPeoplesRemindersDontCount() throws {
        let context = try makeContext()
        let done = insertOpenFollowUp(for: insertPerson("Done", in: context), in: context)
        done.isDone = true
        let removed = insertPerson("Removed", in: context)
        insertOpenFollowUp(for: removed, in: context)
        removed.markDeleted()
        insertOpenFollowUp(for: insertPerson("Open", in: context), in: context)
        #expect(FollowUpPolicy.openCount(in: context) == 1)
    }

    @Test func canScheduleAllowsReschedulingAtTheLimit() throws {
        let context = try makeContext()
        for index in 0..<5 {
            insertOpenFollowUp(for: insertPerson("Person \(index)", in: context), in: context)
        }
        #expect(!FollowUpPolicy.canSchedule(hasOpenReminder: false, in: context, limits: .free))
        #expect(FollowUpPolicy.canSchedule(hasOpenReminder: true, in: context, limits: .free))
        #expect(FollowUpPolicy.canSchedule(hasOpenReminder: false, in: context, limits: .pro))
    }

    // MARK: One open reminder per person

    @Test func captureReschedulesTheExistingReminderInsteadOfAddingOne() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila Yusupova", in: context, telegram: "@kamila")
        let existing = insertOpenFollowUp(for: person, in: context, dueInDays: 10)
        existing.title = "Send the pitch deck"
        let duplicate = insertOpenFollowUp(for: person, in: context, dueInDays: 12)

        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.followUp = FollowUpDraft(pick: .tomorrow, channel: .call, now: testNow, calendar: testCalendar)
        let result = draft.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)

        #expect(result.followUp == .rescheduled(id: existing.id))
        #expect(person.followUps.filter { !$0.isDone && !$0.isDeleted }.count == 1)
        #expect(existing.title == "Send the pitch deck")  // empty "To Do" keeps the title
        #expect(existing.channel == .call)
        #expect(testCalendar.component(.day, from: existing.dueAt) == 27)
        #expect(duplicate.isDeleted)
    }

    @Test func reschedulingWorksEvenAtTheFreeLimit() throws {
        let context = try makeContext()
        for index in 0..<4 {
            insertOpenFollowUp(for: insertPerson("Person \(index)", in: context), in: context)
        }
        let person = insertPerson("Sardor", in: context)
        insertOpenFollowUp(for: person, in: context)
        let result = FollowUpPolicy.schedule(.nextWeek, for: person, in: context, limits: .free,
                                             now: testNow, calendar: testCalendar)
        #expect(result.reminderSet)
        #expect(FollowUpPolicy.openCount(in: context) == 5)
    }

    @Test func scheduleCreatesWithPreferredChannelWhenNoneOpen() throws {
        let context = try makeContext()
        let person = insertPerson("Jasur", in: context, email: "jasur@workly.uz")
        let result = FollowUpPolicy.schedule(.inThreeDays, for: person, in: context, limits: .free,
                                             now: testNow, calendar: testCalendar)
        guard case .scheduled = result.followUp else {
            Issue.record("Expected scheduled, got \(result.followUp)")
            return
        }
        let reminder = try #require(person.openFollowUp)
        #expect(reminder.channel == .email)
        #expect(testCalendar.component(.hour, from: reminder.dueAt) == 10)
    }

    // MARK: Context, note, tags

    @Test func placeWithCommaIsSplitIntoPlaceAndCity() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context)
        var draft = CaptureDraft(context: MeetingContext(metAt: testNow))
        draft.place = "Hyatt Regency, Tashkent"
        draft.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)
        #expect(person.context.place == "Hyatt Regency")
        #expect(person.context.city == "Tashkent")
    }

    @Test func eventLinkIsKeptOnlyWhileTheNameMatches() throws {
        let context = try makeContext()
        let event = Event(name: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent")
        context.insert(event)
        let person = insertPerson("Kamila", in: context)

        let draft = CaptureDraft.capture(for: nil, in: context, now: testNow)
        #expect(draft.eventID == event.id)
        #expect(draft.isAutoFilled)
        draft.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)
        #expect(person.event?.id == event.id)
        #expect(person.context.eventID == event.id)

        var renamed = CaptureDraft(editing: person)
        renamed.eventName = "Coffee"
        #expect(!renamed.isAutoFilled)
        renamed.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)
        #expect(person.event == nil)
        #expect(person.context.eventID == nil)
        #expect(person.context.eventName == "Coffee")
    }

    @Test func newMeetingArchivesThePreviousOneAndAppendsTheNote() throws {
        let context = try makeContext()
        let earlier = MeetingContext(eventName: "Product Meetup", place: "IT Park", city: "Tashkent",
                                     metAt: testCalendar.date(byAdding: .month, value: -2, to: testNow)!)
        let person = insertPerson("Jasur", in: context, context: earlier)
        person.note = "Founder of Workly."
        person.tags = ["Client"]

        let draft = CaptureDraft(intent: .newMeeting,
                                 context: MeetingContext(eventName: "Tashkent Tech Week", metAt: testNow),
                                 note: "Wants a design review in October.", tags: ["investor", "Client"])
        draft.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)

        #expect(person.previousMeetings.first?.eventName == "Product Meetup")
        #expect(person.context.eventName == "Tashkent Tech Week")
        #expect(person.note == "Founder of Workly.\n\nWants a design review in October.")
        #expect(person.tags == ["Client", "investor"])
    }

    @Test func editingContextReplacesWithoutArchiving() throws {
        let context = try makeContext()
        let person = insertPerson("Jasur", in: context,
                                  context: MeetingContext(eventName: "Product Meetup", metAt: testNow))
        person.note = "Old"
        person.tags = ["Client"]
        var draft = CaptureDraft(editing: person)
        draft.eventName = "Product Meetup 2026"
        draft.note = "  New note  "
        draft.tags = ["Partner", " ", "partner"]
        draft.apply(to: person, in: context, limits: .free, now: testNow, calendar: testCalendar)
        #expect(person.previousMeetings.isEmpty)
        #expect(person.note == "New note")
        #expect(person.tags == ["Partner"])
        #expect(person.syncState == .pendingUpsert)
    }

    @Test func captureDraftPrefillsFromTheConnection() throws {
        let context = try makeContext()
        let person = insertPerson("Dilnoza", in: context, phone: "+998 90 000 00 00",
                                  context: MeetingContext(eventName: "Tashkent Tech Week", place: "Hyatt Regency",
                                                          metAt: testNow))
        insertOpenFollowUp(for: person, in: context)
        let draft = CaptureDraft.capture(for: person, in: context, now: testNow)
        #expect(draft.eventName == "Tashkent Tech Week")
        #expect(draft.place == "Hyatt Regency")
        #expect(draft.isAutoFilled)
        // An Uzbek mobile number makes Telegram (by phone) available, so it's preferred over Call.
        #expect(draft.preferredChannel == .telegram)
        #expect(draft.existingReminder != nil)
    }

    // MARK: Channels and links

    @Test func preferredChannelFollowsTelegramEmailCall() {
        #expect(FollowUpPolicy.preferredChannel(phone: "1", email: "a@b.c", telegram: "@x") == .telegram)
        #expect(FollowUpPolicy.preferredChannel(phone: "1", email: "a@b.c", telegram: "") == .email)
        #expect(FollowUpPolicy.preferredChannel(phone: "1", email: " ", telegram: "") == .call)
        #expect(FollowUpPolicy.preferredChannel(phone: "", email: "", telegram: "") == .telegram)
    }

    @Test func contactLinksNormalizeValues() {
        #expect(ContactLinks.telegramHandle("@aziza.k") == "aziza.k")
        #expect(ContactLinks.telegramHandle("https://t.me/aziza_k") == "aziza_k")
        #expect(ContactLinks.telegramHandle("  ") == nil)
        #expect(ContactLinks.telegramApp("@aziza")?.absoluteString == "tg://resolve?domain=aziza")
        #expect(ContactLinks.telegramWeb("aziza")?.absoluteString == "https://t.me/aziza")
        #expect(ContactLinks.call("+998 (90) 123-45-67")?.absoluteString == "tel:+998901234567")
        #expect(ContactLinks.mail("kamila@uzum.uz")?.absoluteString == "mailto:kamila@uzum.uz")
        #expect(ContactLinks.mail("not an email") == nil)
        #expect(ContactLinks.website("aziza.design")?.absoluteString == "https://aziza.design")
        #expect(ContactLinks.linkedIn("in/azizakarimova")?.absoluteString == "https://www.linkedin.com/in/azizakarimova")
    }

    @Test func contactDraftSplitsTheName() {
        let contact = ContactDraft(fullName: "Kamila Yusupova", company: "Uzum", telegram: "@kamila.y").makeContact()
        #expect(contact.givenName == "Kamila")
        #expect(contact.familyName == "Yusupova")
        #expect(contact.organizationName == "Uzum")
        #expect(contact.socialProfiles.first?.value.username == "kamila.y")
    }
}
