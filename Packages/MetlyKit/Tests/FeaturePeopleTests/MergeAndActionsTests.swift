import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeaturePeople

@MainActor
struct MergeAndActionsTests {
    /// Today at 15:00 local, so "same day" checks never straddle midnight.
    private let reference = Calendar.current.date(bySettingHour: 15, minute: 0, second: 0, of: .now)!

    @discardableResult
    private func shareBack(_ name: String, in context: ModelContext, phone: String = "+998 90 111 22 33") -> Connection {
        let person = Connection(fullName: name, jobTitle: "Contact", company: "Shared from your web page",
                                source: .webShareBack, context: MeetingContext(metAt: reference))
        person.createdAt = reference
        person.phone = phone
        person.telegram = "@dilnoza.e"
        context.insert(person)
        return person
    }

    @discardableResult
    private func justMet(_ name: String, in context: ModelContext, minutesAgo: Int = 30, daysAgo: Int = 0) -> Connection {
        var metAt = Calendar.current.date(byAdding: .minute, value: -minutesAgo, to: reference)!
        metAt = Calendar.current.date(byAdding: .day, value: -daysAgo, to: metAt)!
        let person = Connection(fullName: name, source: .justMet,
                                context: MeetingContext(eventName: "Tashkent Tech Week", metAt: metAt))
        person.isPendingMerge = true
        context.insert(person)
        return person
    }

    // MARK: Matching

    @Test func sameFirstNameSameDayIsACandidate() throws {
        let context = try makeContext()
        let web = shareBack("Dilnoza Ergasheva", in: context)
        let pending = justMet("dilnoza", in: context, minutesAgo: 5)
        let people = try context.fetch(Connection.live)
        #expect(ShareBackMerger.candidates(for: web, among: people).map(\.id) == [pending.id])
    }

    @Test func diacriticsAndCaseAreIgnored() {
        #expect(PersonName.firstNamesMatch("Sardór Rashidov", "sardor"))
        #expect(!PersonName.firstNamesMatch("Sardor", "Sanjar"))
        #expect(!PersonName.firstNamesMatch("", "Sardor"))
    }

    @Test func otherDayOrOtherNameIsNotACandidate() throws {
        let context = try makeContext()
        let web = shareBack("Dilnoza Ergasheva", in: context)
        justMet("Dilnoza", in: context, daysAgo: 2)
        justMet("Kamila", in: context)
        let notPending = justMet("Dilnoza", in: context)
        notPending.isPendingMerge = false
        let people = try context.fetch(Connection.live)
        #expect(ShareBackMerger.candidates(for: web, among: people).isEmpty)
    }

    @Test func namelessJustMetIsOfferedAfterNameMatches() throws {
        let context = try makeContext()
        let web = shareBack("Dilnoza Ergasheva", in: context)
        let nameless = justMet(JustMetNaming.placeholder(eventName: "Tashkent Tech Week"), in: context, minutesAgo: 1)
        let named = justMet("Dilnoza", in: context, minutesAgo: 120)
        let people = try context.fetch(Connection.live)
        #expect(ShareBackMerger.candidates(for: web, among: people).map(\.id) == [named.id, nameless.id])
    }

    @Test func onlyWebShareBacksGetCandidates() throws {
        let context = try makeContext()
        let nearby = insertPerson("Dilnoza Ergasheva", in: context)
        justMet("Dilnoza", in: context)
        let people = try context.fetch(Connection.live)
        #expect(ShareBackMerger.candidates(for: nearby, among: people).isEmpty)
    }

    // MARK: Merge

    @Test func mergeCopiesFieldsMarksMergedAndRemovesTheDuplicate() throws {
        let context = try makeContext()
        let web = shareBack("Dilnoza Ergasheva", in: context)
        let pending = justMet("Dilnoza", in: context)
        pending.note = "Hiring two designers"
        pending.tags = ["Hiring"]

        ShareBackMerger.merge(web, into: pending, in: context)

        #expect(pending.isMerged)
        #expect(!pending.isPendingMerge)
        #expect(pending.fullName == "Dilnoza Ergasheva")
        #expect(pending.phone == "+998 90 111 22 33")
        #expect(pending.telegram == "@dilnoza.e")
        #expect(pending.note == "Hiring two designers")
        #expect(pending.context.eventName == "Tashkent Tech Week")
        #expect(web.isDeleted)
        let live = try context.fetch(Connection.live)
        #expect(live.map(\.id) == [pending.id])
    }

    @Test func mergeKeepsOneOpenReminder() throws {
        let context = try makeContext()
        let web = shareBack("Dilnoza Ergasheva", in: context)
        let pending = justMet("Dilnoza", in: context)
        let theirs = insertOpenFollowUp(for: web, in: context)
        ShareBackMerger.merge(web, into: pending, in: context)
        #expect(theirs.connection?.id == pending.id)
        #expect(pending.openFollowUp?.id == theirs.id)
    }

    // MARK: Remove / block / requests

    @Test func removeSoftDeletesPersonAndRemindersAndUndoRestores() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila", in: context)
        let reminder = insertOpenFollowUp(for: person, in: context)

        let undo = PeopleActions.remove(person, in: context)
        #expect(person.isDeleted)
        #expect(reminder.isDeleted)
        #expect(try context.fetch(Connection.live).isEmpty)

        undo()
        #expect(!person.isDeleted)
        #expect(!reminder.isDeleted)
        #expect(person.syncState == .pendingUpsert)
    }

    @Test func blockHidesFromPeopleAndUnblockBringsBack() throws {
        let context = try makeContext()
        let person = insertPerson("Sardor", in: context)
        PeopleActions.block(person, in: context)
        #expect(try context.fetch(Connection.live).isEmpty)
        PeopleActions.unblock(person, in: context)
        #expect(try context.fetch(Connection.live).count == 1)
    }

    @Test func acceptingARequestCreatesATaggedConnection() throws {
        let context = try makeContext()
        let event = Event(name: "Tashkent Tech Week", place: "Hyatt Regency", city: "Tashkent")
        context.insert(event)
        let card = CardSnapshot(cardName: "Work", design: CardDesign(), fullName: "Bekzod Tursunov",
                                jobTitle: "Growth Lead", company: "Alif",
                                fields: [ContactField(kind: .telegram, value: "@bekzod")])
        let request = ConnectRequest(direction: .incoming, peerUserID: UUID(), peerName: "Bekzod Tursunov",
                                     peerTitle: "Growth Lead", peerCompany: "Alif", peerCard: card, method: .nearby)
        context.insert(request)

        let person = PeopleActions.accept(request, in: context, now: testNow)

        #expect(person.source == .connectRequest)
        #expect(person.remoteUserID == request.peerUserID)
        #expect(person.telegram == "@bekzod")
        #expect(person.theirCard?.cardName == "Work")
        #expect(person.event?.id == event.id)
        #expect(person.context.eventName == "Tashkent Tech Week")
        #expect(request.status == .accepted)
        #expect(request.respondedAt == testNow)
        #expect(try context.fetch(ConnectRequest.pendingIncoming).isEmpty)
    }

    @Test func acceptingAKnownPeerReusesTheirConnection() throws {
        let context = try makeContext()
        let peerID = UUID()
        let known = insertPerson("Bekzod Tursunov", in: context,
                                 context: MeetingContext(eventName: "Product Meetup", metAt: testNow))
        known.remoteUserID = peerID
        let request = ConnectRequest(direction: .incoming, peerUserID: peerID, peerName: "Bekzod Tursunov",
                                     method: .nearby, eventName: "Founders Dinner")
        context.insert(request)

        let person = PeopleActions.accept(request, in: context, now: testNow)
        #expect(person.id == known.id)
        #expect(person.previousMeetings.first?.eventName == "Product Meetup")
        #expect(person.context.eventName == "Founders Dinner")
        #expect(try context.fetch(Connection.live).count == 1)
    }

    @Test func decliningMarksTheRequestDeclined() throws {
        let context = try makeContext()
        let request = ConnectRequest(direction: .incoming, peerUserID: UUID(), peerName: "Kamila", method: .nearby)
        context.insert(request)
        PeopleActions.decline(request, in: context, now: testNow)
        #expect(request.status == .declined)
        #expect(try context.fetch(ConnectRequest.pendingIncoming).isEmpty)
    }

    @Test func markDoneAndUndo() throws {
        let context = try makeContext()
        let reminder = insertOpenFollowUp(for: insertPerson("Jasur", in: context), in: context)
        let undo = PeopleActions.markDone(reminder, in: context)
        #expect(reminder.isDone)
        #expect(reminder.completedAt != nil)
        undo()
        #expect(!reminder.isDone)
        #expect(reminder.completedAt == nil)
    }

    @Test func justMetPlaceholderNames() {
        #expect(JustMetNaming.placeholder(eventName: "Tashkent Tech Week") == "Someone at Tashkent Tech Week")
        #expect(JustMetNaming.placeholder(eventName: nil) == "Someone You Met")
        #expect(JustMetNaming.isPlaceholder("Someone You Met"))
        #expect(!JustMetNaming.isPlaceholder("Somebody"))
    }
}
