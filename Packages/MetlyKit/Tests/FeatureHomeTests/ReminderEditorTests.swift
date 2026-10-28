import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureHome

@MainActor
struct ReminderFormTests {
    @Test func newReminderDefaultsToTomorrowAtTen() {
        let form = ReminderForm.new(personID: nil, channel: .email, now: testNow, calendar: testCalendar)
        let due = components(form.dueDate(calendar: testCalendar))
        #expect(due.day == 27)
        #expect(due.hour == 10)
        #expect(due.minute == 0)
        #expect(form.title.isEmpty)
        #expect(form.resolvedTitle == "Follow up")
        #expect(!form.canSave)
    }

    @Test func editingShowsCustomTitleAndHidesDefault() {
        let custom = ReminderForm.editing(title: "Send deck", dueAt: date(2026, 9, 29, 16, 30), channel: .call,
                                          personID: UUID(), calendar: testCalendar)
        #expect(custom.title == "Send deck")
        #expect(components(custom.dueDate(calendar: testCalendar)).hour == 16)
        #expect(custom.canSave)

        let plain = ReminderForm.editing(title: "Follow up", dueAt: testNow, channel: .call, personID: nil, calendar: testCalendar)
        #expect(plain.title.isEmpty)
        #expect(plain.resolvedTitle == "Follow up")
    }

    @Test func titleIsTrimmed() {
        var form = ReminderForm.new(personID: nil, channel: .telegram, now: testNow, calendar: testCalendar)
        form.title = "  Send the deck \n"
        #expect(form.resolvedTitle == "Send the deck")
    }

    @Test func summaryNamesTheDay() {
        var form = ReminderForm.new(personID: nil, channel: .telegram, now: testNow, calendar: testCalendar)
        #expect(form.summary(now: testNow, calendar: testCalendar, locale: usLocale).hasPrefix("Tanishly will remind you tomorrow at 10:00"))

        form.day = date(2026, 9, 29)
        #expect(form.summary(now: testNow, calendar: testCalendar, locale: usLocale).hasPrefix("Tanishly will remind you on Tue, Sep 29 at 10:00"))

        form.day = date(2026, 9, 26)
        form.time = date(2026, 9, 26, 18, 0)
        #expect(form.summary(now: testNow, calendar: testCalendar, locale: usLocale).hasPrefix("Tanishly will remind you today at 6:00"))

        form.time = date(2026, 9, 26, 9, 0)
        #expect(form.summary(now: testNow, calendar: testCalendar, locale: usLocale).hasPrefix("This time has already passed"))
    }

    @Test func minimumDayAllowsAnOverdueReminderToKeepItsDay() {
        let today = testCalendar.startOfDay(for: testNow)
        #expect(ReminderForm.minimumDay(existingDue: nil, now: testNow, calendar: testCalendar) == today)
        #expect(ReminderForm.minimumDay(existingDue: date(2026, 9, 30), now: testNow, calendar: testCalendar) == today)
        let overdue = date(2026, 9, 20)
        #expect(ReminderForm.minimumDay(existingDue: overdue, now: testNow, calendar: testCalendar)
            == testCalendar.startOfDay(for: overdue))
    }
}

@MainActor
struct ReminderEditorTests {
    @Test func createsReminderForPerson() throws {
        let context = try makeContext()
        let kamila = insertPerson("Kamila Yusupova", in: context, telegram: "@kamila")
        var form = ReminderForm.new(personID: kamila.id, channel: .telegram, now: testNow, calendar: testCalendar)
        form.title = "Send deck"

        let result = ReminderEditor.save(form, existing: nil, in: context, limits: .free, calendar: testCalendar)
        guard case .created(let id) = result else {
            Issue.record("Expected a new reminder, got \(result)")
            return
        }
        let reminder = try #require(context.record(FollowUp.self, id: id))
        #expect(reminder.title == "Send deck")
        #expect(reminder.connection?.id == kamila.id)
        #expect(components(reminder.dueAt).day == 27)
        #expect(reminder.syncState == .pendingUpsert)
    }

    @Test func editorMayAddASecondOpenReminderForTheSamePerson() throws {
        let context = try makeContext()
        let kamila = insertPerson("Kamila", in: context)
        insertReminder(for: kamila, in: context)
        try context.save()
        let form = ReminderForm.new(personID: kamila.id, channel: .telegram, now: testNow, calendar: testCalendar)

        _ = ReminderEditor.save(form, existing: nil, in: context, limits: .free, calendar: testCalendar)
        #expect(kamila.followUps.count { !$0.isDone && !$0.isDeleted } == 2)
    }

    @Test func freePlanStopsAtFiveOpenReminders() throws {
        let context = try makeContext()
        let person = insertPerson("Sardor", in: context)
        for _ in 0..<5 { insertReminder(for: person, in: context) }
        try context.save()
        let form = ReminderForm.new(personID: person.id, channel: .call, now: testNow, calendar: testCalendar)

        #expect(ReminderEditor.save(form, existing: nil, in: context, limits: .free, calendar: testCalendar) == .limitReached(openCount: 5))
        guard case .created = ReminderEditor.save(form, existing: nil, in: context, limits: .pro, calendar: testCalendar) else {
            Issue.record("Pro should not be limited")
            return
        }
    }

    @Test func doneRemindersDoNotCountTowardTheLimit() throws {
        let context = try makeContext()
        let person = insertPerson("Dilnoza", in: context)
        for index in 0..<5 {
            let reminder = insertReminder(for: person, in: context)
            reminder.isDone = index == 0
        }
        try context.save()
        let form = ReminderForm.new(personID: person.id, channel: .call, now: testNow, calendar: testCalendar)
        guard case .created = ReminderEditor.save(form, existing: nil, in: context, limits: .free, calendar: testCalendar) else {
            Issue.record("Four open reminders leave room for a fifth")
            return
        }
    }

    @Test func updatingNeverHitsTheLimit() throws {
        let context = try makeContext()
        let person = insertPerson("Jasur", in: context)
        let reminders = (0..<5).map { _ in insertReminder(for: person, in: context) }
        try context.save()
        var form = ReminderForm.editing(title: "Follow up", dueAt: reminders[0].dueAt, channel: .call,
                                        personID: person.id, calendar: testCalendar)
        form.title = "Design review"
        form.channel = .email
        form.day = date(2026, 10, 5)

        #expect(ReminderEditor.save(form, existing: reminders[0], in: context, limits: .free, calendar: testCalendar)
            == .updated(id: reminders[0].id))
        #expect(reminders[0].title == "Design review")
        #expect(reminders[0].channel == .email)
        #expect(components(reminders[0].dueAt).month == 10)
    }

    @Test func requiresAPerson() throws {
        let context = try makeContext()
        let form = ReminderForm.new(personID: nil, channel: .call, now: testNow, calendar: testCalendar)
        #expect(ReminderEditor.save(form, existing: nil, in: context, limits: .free, calendar: testCalendar) == .missingPerson)
    }
}

@MainActor
struct FollowUpMutationTests {
    @Test func doneAndUndo() throws {
        let context = try makeContext()
        let reminder = insertReminder(for: insertPerson("Kamila", in: context), in: context)
        let undo = FollowUpMutations.markDone(reminder, in: context, now: testNow)
        #expect(reminder.isDone)
        #expect(reminder.completedAt == testNow)
        undo()
        #expect(!reminder.isDone)
        #expect(reminder.completedAt == nil)
    }

    @Test func rescheduleAndUndo() throws {
        let context = try makeContext()
        let reminder = insertReminder(for: nil, in: context, dueAt: date(2026, 9, 25))
        let undo = FollowUpMutations.reschedule(reminder, to: date(2026, 9, 27), in: context)
        #expect(components(reminder.dueAt).day == 27)
        undo()
        #expect(components(reminder.dueAt).day == 25)
    }

    @Test func deleteIsSoftAndUndoable() throws {
        let context = try makeContext()
        let reminder = insertReminder(for: nil, in: context)
        let undo = FollowUpMutations.delete(reminder, in: context)
        #expect(reminder.isDeleted)
        #expect(reminder.syncState == .pendingDelete)
        #expect(try context.fetch(FollowUp.open).isEmpty)
        undo()
        #expect(!reminder.isDeleted)
        #expect(try context.fetch(FollowUp.open).count == 1)
    }
}

@MainActor
struct ChannelLinkTests {
    @Test func availableChannelsFollowContactValues() throws {
        let context = try makeContext()
        let telegramOnly = insertPerson("A", in: context, telegram: "@a")
        #expect(ChannelLink.availableChannels(for: telegramOnly) == [.telegram])
        let all = insertPerson("B", in: context, telegram: "@b", email: "b@x.uz", phone: "+998 90 000 00 00")
        #expect(ChannelLink.availableChannels(for: all) == Set(FollowUpChannel.allCases))
        let none = insertPerson("C", in: context)
        #expect(ChannelLink.availableChannels(for: none) == Set(FollowUpChannel.allCases))
    }

    @Test func urlsPerChannel() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context, telegram: "@kamila.y", email: "kamila@uzum.uz",
                                  phone: "+998 90 123 45 67")
        let telegram = try #require(ChannelLink.target(.telegram, for: person))
        #expect(telegram.primary.absoluteString == "tg://resolve?domain=kamila.y")
        #expect(telegram.fallback?.absoluteString == "https://t.me/kamila.y")
        #expect(!telegram.isTelegramByPhone)
        #expect(ChannelLink.target(.email, for: person) == ChannelLink.Target(primary: URL(string: "mailto:kamila@uzum.uz")!))
        #expect(ChannelLink.target(.call, for: person)?.primary.absoluteString == "tel:+998901234567")
        #expect(ChannelLink.target(.call, for: insertPerson("Nobody", in: context)) == nil)
        #expect(ChannelLink.target(.telegram, for: nil) == nil)
    }

    @Test func telegramOpensByTheMobileNumberWithoutAUsername() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context, phone: "90 123-45-67")
        let target = try #require(ChannelLink.target(.telegram, for: person))
        #expect(target.primary.absoluteString == "tg://resolve?phone=998901234567")
        #expect(target.fallback?.absoluteString == "https://t.me/+998901234567")
        #expect(target.isTelegramByPhone)
        #expect(ChannelLink.availableChannels(for: person) == [.telegram, .call])

        let russian = insertPerson("Ivan", in: context, phone: "+7 912 345-67-89")
        #expect(ChannelLink.target(.telegram, for: russian)?.primary.absoluteString == "tg://resolve?phone=79123456789")
    }

    @Test func aLandlineDoesNotOfferTelegram() throws {
        let context = try makeContext()
        let office = insertPerson("Office", in: context, phone: "+998 71 200 00 00")
        #expect(ChannelLink.target(.telegram, for: office) == nil)
        #expect(ChannelLink.availableChannels(for: office) == [.call])
        #expect(ChannelLink.missingValueNote(.telegram, firstName: "Office") == "Office has no Telegram username or mobile number saved.")
    }

    /// With several numbers a reminder's Call (and notification action) dials the mobile one.
    @Test func callUsesTheMobileNumber() throws {
        let context = try makeContext()
        let person = insertPerson("Madina", in: context, phone: "+998 71 200 00 00")
        person.phoneLabel = .work
        person.additionalPhones = [LabeledPhone(label: .home, value: "+998 66 233 00 00"),
                                   LabeledPhone(label: .mobile, value: "+998 93 555 12 34")]
        #expect(ChannelLink.callNumber(for: person) == "+998 93 555 12 34")
        #expect(ChannelLink.target(.call, for: person)?.primary.absoluteString == "tel:+998935551234")

        // No mobile number: the primary one.
        person.additionalPhones = [LabeledPhone(label: .home, value: "+998 66 233 00 00")]
        #expect(ChannelLink.callNumber(for: person) == "+998 71 200 00 00")

        // Only extra numbers saved (the primary was cleared).
        person.phone = ""
        #expect(ChannelLink.callNumber(for: person) == "+998 66 233 00 00")
    }

    @Test func actionTitles() {
        #expect(ChannelLink.actionTitle(.telegram) == "Telegram")
        #expect(ChannelLink.actionTitle(.email) == "Mail")
        #expect(ChannelLink.actionTitle(.call) == "Call")
    }
}
