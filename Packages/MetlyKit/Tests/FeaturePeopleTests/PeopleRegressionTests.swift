import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeaturePeople

@MainActor
struct PeopleRegressionTests {

    // MARK: Remove → sync → Undo

    /// Regression: the sync engine pushes the tombstone ~1.5 s after Remove and hard-deletes the local
    /// record when the server confirms — inside the 4 s Undo window. Undo must still bring the person back.
    @Test func undoAfterTheSyncHardDeletedThePersonRestoresEverything() throws {
        let context = try makeContext()
        let person = insertPerson("Kamila Yusupova", in: context, telegram: "@kamila")
        person.note = "Pitch deck in October"
        person.tags = ["Investor"]
        person.remoteUserID = UUID()
        let reminder = insertOpenFollowUp(for: person, in: context)
        try context.save()
        let personID = person.id
        let reminderID = reminder.id

        let undo = PeopleActions.remove(person, in: context)
        // What SyncApplier does with the server's tombstone echo (cascade removes the reminder too).
        context.delete(person)
        try context.save()
        #expect(context.record(Connection.self, id: personID) == nil)

        undo()

        let restored = try #require(context.record(Connection.self, id: personID))
        #expect(!restored.isDeleted)
        #expect(restored.fullName == "Kamila Yusupova")
        #expect(restored.note == "Pitch deck in October")
        #expect(restored.tags == ["Investor"])
        #expect(restored.telegram == "@kamila")
        #expect(restored.syncState == .pendingUpsert)
        #expect(try context.fetch(Connection.live).map(\.id) == [personID])
        let restoredReminder = try #require(context.record(FollowUp.self, id: reminderID))
        #expect(!restoredReminder.isDeleted)
        #expect(restoredReminder.connection?.id == personID)
        #expect(restoredReminder.syncState == .pendingUpsert)
        #expect(restored.openFollowUp?.id == reminderID)
    }

    // MARK: Place / city

    @Test func meetingPlaceNamesTheCityOnce() {
        let context = MeetingContext(place: "Hyatt Regency, Tashkent", city: "Tashkent")
        #expect(MeetingFormatting.place(context) == "Hyatt Regency, Tashkent")
        #expect(MeetingFormatting.place(MeetingContext(place: "Tashkent", city: "Tashkent")) == "Tashkent")
        #expect(MeetingFormatting.place(MeetingContext(place: "IT Park", city: "Samarkand")) == "IT Park, Samarkand")
    }

    @Test func eventCardsNameTheCityOnce() throws {
        let context = try makeContext()
        let event = Event(name: "Tashkent Tech Week", place: "Hyatt Regency, Tashkent", city: "Tashkent")
        context.insert(event)
        let person = insertPerson("Kamila", in: context,
                                  context: MeetingContext(eventName: "Founders Dinner", place: "Plov Center, Tashkent",
                                                          city: "Tashkent", metAt: testNow))
        let summaries = PeopleIndex.eventSummaries(people: [person], events: [event])
        #expect(summaries.first { $0.eventID == event.id }?.place == "Hyatt Regency, Tashkent")
        #expect(summaries.first { $0.eventID == nil }?.place == "Plov Center, Tashkent")
    }

    @Test func acceptingDuringAnEventSavesThePlaceWithoutTheCity() throws {
        let context = try makeContext()
        context.insert(Event(name: "Tashkent Tech Week", place: "Hyatt Regency, Tashkent", city: "Tashkent"))
        let request = ConnectRequest(direction: .incoming, peerUserID: UUID(), peerName: "Bekzod Tursunov", method: .scan)
        context.insert(request)
        let person = PeopleActions.accept(request, in: context, now: testNow)
        #expect(person.context.place == "Hyatt Regency")
        #expect(person.context.city == "Tashkent")
    }

    // MARK: Requests

    private func request(from peerID: UUID = UUID(), name: String = "Bekzod Tursunov", method: ConnectMethod = .scan,
                         createdAt: Date = testNow, expiresAt: Date? = nil, in context: ModelContext) -> ConnectRequest {
        let request = ConnectRequest(direction: .incoming, peerUserID: peerID, peerName: name, method: method)
        request.createdAt = createdAt
        request.expiresAt = expiresAt
        context.insert(request)
        return request
    }

    /// Regression: People › Requests offered a live request whose 60 s had passed — accepting it created a
    /// one-sided connection and showed "You're Connected" while the server rejected the accept.
    @Test func expiredRequestsAreNotOffered() throws {
        let context = try makeContext()
        let expired = request(method: .nearby, expiresAt: testNow.addingTimeInterval(-1), in: context)
        let live = request(method: .nearby, expiresAt: testNow.addingTimeInterval(30), in: context)
        let scanned = request(method: .scan, expiresAt: nil, in: context)
        let visible = RequestVisibility.visible([expired, live, scanned], blockedUserIDs: [], now: testNow)
        #expect(Set(visible.map(\.id)) == [live.id, scanned.id])
        #expect(!RequestVisibility.isAnswerable(expired, blockedUserIDs: [], now: testNow))
    }

    /// Regression: a request that arrived before the owner blocked the sender stayed in Requests, and
    /// accepting it silently unblocked them.
    @Test func requestsFromBlockedPeopleAreNotOffered() throws {
        let context = try makeContext()
        let blockedID = UUID()
        let fromBlocked = request(from: blockedID, in: context)
        let other = request(in: context)
        let visible = RequestVisibility.visible([fromBlocked, other], blockedUserIDs: [blockedID], now: testNow)
        #expect(visible.map(\.id) == [other.id])
    }

    @Test func onePendingRequestPerPersonIsOffered() throws {
        let context = try makeContext()
        let peerID = UUID()
        let older = request(from: peerID, createdAt: testNow.addingTimeInterval(-600), in: context)
        let newer = request(from: peerID, createdAt: testNow, in: context)
        #expect(RequestVisibility.visible([older, newer], blockedUserIDs: [], now: testNow).map(\.id) == [newer.id])
    }

    /// Accepting settles the other pending requests from the same person (as the server does), so Requests
    /// doesn't ask about them again right after connecting.
    @Test func acceptingSettlesOtherRequestsFromTheSamePerson() throws {
        let context = try makeContext()
        let peerID = UUID()
        let older = request(from: peerID, createdAt: testNow.addingTimeInterval(-600), in: context)
        let newer = request(from: peerID, createdAt: testNow, in: context)
        let unrelated = request(in: context)
        PeopleActions.accept(newer, in: context, now: testNow)
        #expect(older.status == .accepted)
        #expect(older.syncState == .synced)   // the server settles it; nothing to push
        #expect(newer.syncState == .pendingUpsert)
        #expect(try context.fetch(ConnectRequest.pendingIncoming).map(\.id) == [unrelated.id])
    }
}
