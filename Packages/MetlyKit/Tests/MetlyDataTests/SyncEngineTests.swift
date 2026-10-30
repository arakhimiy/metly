import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import Testing
@testable import MetlyData

@MainActor
@Suite("SyncEngine")
struct SyncEngineTests {

    // MARK: Pull

    @Test("A full pull fills an empty store with the server's account")
    func initialPull() async throws {
        let harness = try SyncHarness(local: .signedOut, server: .demo)
        await harness.engine.syncNow()

        #expect(harness.engine.status == .idle)
        #expect(harness.engine.lastSyncedAt != nil)
        #expect(harness.state.cursor != nil)
        #expect(harness.count(Profile.self) == 1)
        #expect(harness.count(Card.self) == 2)
        #expect(harness.count(Event.self) == 1)
        #expect(harness.count(Connection.self) == 6)
        #expect(harness.count(FollowUp.self) == 4)
        #expect(harness.count(ConnectRequest.self) == 1)
        #expect(harness.context.currentProfile()?.fullName == "Aziza Karimova")
        #expect(harness.connection(MockSeed.connectionIDs[0])?.event?.id == MockSeed.eventID)
        #expect(harness.context.record(FollowUp.self, id: MockSeed.followUpIDs[0])?.connection?.id == MockSeed.connectionIDs[0])
        #expect(harness.all(Connection.self).allSatisfy { $0.syncState == .synced })
        #expect(harness.context.record(Card.self, id: MockSeed.workCardID)?.slug == "aziza-w7k2")
    }

    @Test("Demo data on the device + demo account on the server → no duplicates")
    func seededDeviceDoesNotDuplicate() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        await harness.engine.syncNow()
        #expect(harness.engine.status == .idle)
        #expect(harness.count(Card.self) == 2)
        #expect(harness.count(Connection.self) == 6)
        #expect(harness.count(FollowUp.self) == 4)
        #expect(harness.count(ConnectRequest.self) == 1)
    }

    // MARK: Push

    @Test("New local records are pushed and marked synced")
    func pushNewRecord() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let person = Connection(fullName: "Nilufar Sobirova", jobTitle: "Designer", source: .paper)
        harness.context.insert(person)
        let reminder = FollowUp(title: "Send portfolio", channel: .email, dueAt: .now.addingTimeInterval(86_400), connection: person)
        harness.context.insert(reminder)
        try harness.context.save()
        #expect(harness.engine.hasPushableChanges())

        await harness.engine.syncNow()

        #expect(person.syncState == .synced)
        #expect(reminder.syncState == .synced)
        #expect(!harness.engine.hasPushableChanges())
        let server = await harness.server.liveRecords()
        #expect(server.connections.contains { $0.id == person.id && $0.fullName == "Nilufar Sobirova" })
        #expect(server.followUps.contains { $0.id == reminder.id && $0.connectionID == person.id })
    }

    @Test("A draft card gets its slug on push (profile first, then card)")
    func pushPublishesDraftCard() async throws {
        let harness = try SyncHarness(local: .signedOut, server: .newAccount)
        let profile = Profile(fullName: "Dilnoza Ergasheva", isSetupComplete: true)
        harness.context.insert(profile)
        let card = Card(name: "Work")
        harness.context.insert(card)
        profile.defaultCardID = card.id
        try harness.context.save()
        #expect(card.publishState == .draft)
        #expect(card.url == nil)

        await harness.engine.syncNow()

        #expect(card.syncState == .synced)
        #expect(card.publishState == .published)
        #expect(card.slug.wholeMatch(of: /dilnoza-[a-z0-9]{4}/) != nil)
        #expect(profile.syncState == .synced)
    }

    @Test("Deletes push a tombstone, cascade on the server and hard-delete locally")
    func pushTombstone() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let kamila = try #require(harness.connection(MockSeed.connectionIDs[0]))
        kamila.markDeleted()
        try harness.context.save()
        #expect(try harness.context.fetch(Connection.live).count == 5)   // soft-deleted is hidden immediately

        await harness.engine.syncNow()

        #expect(harness.connection(MockSeed.connectionIDs[0]) == nil)
        #expect(harness.context.record(FollowUp.self, id: MockSeed.followUpIDs[0]) == nil)   // cascade
        let tombstones = await harness.server.tombstoneIDs
        #expect(tombstones.contains(MockSeed.connectionIDs[0]))
        #expect(tombstones.contains(MockSeed.followUpIDs[0]))
    }

    @Test("Share-back merge pair (soft-delete + update) syncs cleanly")
    func shareBackMergePair() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let notice = await harness.server.simulateShareBack(name: "Timur", telegram: "@timur.web")
        await harness.engine.syncNow()
        let shared = try #require(harness.connection(notice.connection.id))
        let justMet = try #require(harness.connection(MockSeed.connectionIDs[5]))

        justMet.telegram = shared.telegram
        justMet.isMerged = true
        justMet.markChanged()
        shared.markDeleted()
        try harness.context.save()
        await harness.engine.syncNow()

        #expect(harness.connection(notice.connection.id) == nil)
        #expect(justMet.syncState == .synced)
        let live = await harness.server.liveRecords().connections
        #expect(!live.contains { $0.id == notice.connection.id })
        #expect(live.first { $0.id == justMet.id }?.isMerged == true)
    }

    // MARK: Last write wins

    @Test("A newer remote edit beats an older local edit")
    func remoteNewerWins() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let sardor = try #require(harness.connection(MockSeed.connectionIDs[1]))
        sardor.note = "Local note"
        sardor.markChanged()
        try harness.context.save()

        var remote = sardor.dto
        remote.note = "Edited on iPad"
        remote.updatedAt = .now.addingTimeInterval(60)
        await harness.server.simulateRemoteChanges(SyncChanges(connections: [remote]))

        await harness.engine.syncNow()
        #expect(sardor.note == "Edited on iPad")
        #expect(sardor.syncState == .synced)
    }

    @Test("A newer local edit beats an older remote edit")
    func localNewerWins() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let jasur = try #require(harness.connection(MockSeed.connectionIDs[3]))
        var remote = jasur.dto
        remote.note = "Older remote note"
        remote.updatedAt = jasur.updatedAt.addingTimeInterval(1)
        await harness.server.simulateRemoteChanges(SyncChanges(connections: [remote]))

        jasur.note = "Fresh local note"
        jasur.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()

        #expect(jasur.note == "Fresh local note")
        #expect(jasur.syncState == .synced)
        let server = await harness.server.liveRecords().connections.first { $0.id == jasur.id }
        #expect(server?.note == "Fresh local note")
    }

    @Test("Pulls never overwrite a dirty record with older data, but take server-owned fields")
    func pullKeepsDirtyLocalEdits() throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let card = try #require(harness.context.record(Card.self, id: MockSeed.personalCardID))
        card.name = "Weekend"
        card.markChanged()

        var remote = card.dto
        remote.name = "Personal (older)"
        remote.updatedAt = card.updatedAt.addingTimeInterval(-30)
        remote.stats = CardStats(views: 77)
        var applier = SyncApplier(context: harness.context, mode: .pull)
        applier.apply(SyncChanges(cards: [remote]))

        #expect(card.name == "Weekend")
        #expect(card.syncState == .pendingUpsert)
        #expect(card.stats.views == 77)
    }

    @Test("A remote tombstone deletes a synced local record")
    func remoteTombstone() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        await harness.server.simulateRemoteChanges(SyncChanges(tombstones: [
            TombstoneDTO(type: .card, id: MockSeed.personalCardID, deletedAt: .now),
        ]))
        await harness.engine.syncNow()
        #expect(harness.context.record(Card.self, id: MockSeed.personalCardID) == nil)
        #expect(harness.count(Card.self) == 1)
    }

    @Test("A remote tombstone loses against a newer local edit (record is re-created)")
    func localEditBeatsOlderTombstone() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let madina = try #require(harness.connection(MockSeed.connectionIDs[4]))
        await harness.server.simulateRemoteChanges(SyncChanges(tombstones: [
            TombstoneDTO(type: .connection, id: madina.id, deletedAt: .now.addingTimeInterval(-5)),
        ]))
        madina.note = "Still relevant"
        madina.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()

        #expect(harness.connection(MockSeed.connectionIDs[4])?.note == "Still relevant")
        let server = await harness.server.liveRecords().connections
        #expect(server.contains { $0.id == madina.id && $0.note == "Still relevant" })
    }

    // MARK: Failure handling

    @Test("Plan-limit rejections are not re-pushed until the record changes")
    func rejectedIsNotRetried() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let third = Card(name: "Conference", sortOrder: 2)
        harness.context.insert(third)
        try harness.context.save()

        await harness.engine.syncNow()
        #expect(third.syncState == .pendingUpsert)
        #expect(harness.state.isRejected(third.id, updatedAt: third.updatedAt))
        #expect(!harness.engine.hasPushableChanges())

        let calls = await harness.server.callCount
        await harness.engine.syncNow()
        let pushedAgain = await harness.server.liveRecords().cards.contains { $0.id == third.id }
        #expect(!pushedAgain)
        #expect(await harness.server.callCount - calls == 1)   // just the pull

        third.name = "Conference 2026"
        third.markChanged()
        #expect(harness.engine.hasPushableChanges())
    }

    @Test("Offline: nothing is sent and status says so")
    func offlinePauses() async throws {
        let harness = try SyncHarness(local: .full, server: .demo, online: false)
        harness.context.insert(Connection(fullName: "Offline Person", source: .paper))
        try harness.context.save()
        await harness.engine.syncNow()
        #expect(harness.engine.status == .offline)
        #expect(await harness.server.callCount == 0)
    }

    @Test("Server unreachable → .offline and a retry is scheduled; local data untouched")
    func serverDown() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.server.setReachable(false)
        await harness.engine.syncNow()
        #expect(harness.engine.status == .offline)
        #expect(harness.count(Connection.self) == 6)
        harness.engine.reset()
    }

    @Test("Signed out → the engine stays idle")
    func gatedBySignIn() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        harness.engine.shouldSync = { false }
        await harness.engine.syncNow()
        #expect(harness.engine.status == .idle)
        #expect(await harness.server.callCount == 0)
    }

    @Test("An expired cursor triggers a full snapshot that also prunes records the server lost")
    func expiredCursorResync() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let ghost = Connection(fullName: "Ghost", source: .manual)
        ghost.syncState = .synced
        harness.context.insert(ghost)
        try harness.context.save()
        harness.state.cursor = "mock:999999"

        await harness.engine.syncNow()

        #expect(harness.engine.status == .idle)
        #expect(harness.connection(ghost.id) == nil)
        #expect(harness.count(Connection.self) == 6)
        #expect(harness.state.cursor != "mock:999999")
    }

    // MARK: Connect requests & images

    @Test("An accept queued offline becomes POST …/accept; the optimistic connection isn't duplicated")
    func queuedAccept() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let request = try #require(harness.context.record(ConnectRequest.self, id: MockSeed.incomingRequestID))
        // What People does: accept locally and create the connection right away.
        request.status = .accepted
        request.myCardID = MockSeed.workCardID
        request.markChanged()
        let optimistic = Connection(fullName: request.peerName, jobTitle: request.peerTitle, company: request.peerCompany,
                                    source: .connectRequest)
        optimistic.remoteUserID = request.peerUserID
        harness.context.insert(optimistic)
        try harness.context.save()

        await harness.engine.syncNow()

        #expect(request.syncState == .synced)
        #expect(request.status == .accepted)
        let bekzods = harness.all(Connection.self).filter { $0.remoteUserID == request.peerUserID }
        #expect(bekzods.count == 1)
        #expect(bekzods.first?.syncState == .synced)
        let serverRequest = try await harness.server.fetchRequest(id: request.id)
        #expect(serverRequest.status == .accepted)
    }

    @Test("A decline queued offline becomes POST …/decline")
    func queuedDecline() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let request = try #require(harness.context.record(ConnectRequest.self, id: MockSeed.incomingRequestID))
        request.status = .declined
        request.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()
        #expect(request.syncState == .synced)
        #expect(try await harness.server.fetchRequest(id: request.id).status == .declined)
    }

    @Test("A photo upload the server can't take doesn't hold back the rest of the sync")
    func imageFailureDoesNotBlockPull() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        await harness.server.setImageStorage(false)
        let profile = try #require(harness.context.currentProfile())
        profile.photoData = TestImage.jpeg
        profile.markChanged()
        try harness.context.save()

        // A web visitor shares their contact while the photo can't be uploaded.
        let notice = await harness.server.simulateShareBack(name: "Azamat", phone: "+998 90 555 44 33")
        await harness.engine.syncNow()
        #expect(harness.all(Connection.self).contains { $0.id == notice.connection.id })
        #expect(await harness.server.liveRecords().profile?.photoURL == nil)

        // Once storage is back, the photo goes up on the next pass.
        await harness.server.setImageStorage(true)
        await harness.engine.syncNow()
        #expect(await harness.server.liveRecords().profile?.photoURL != nil)
        harness.engine.reset()
    }

    @Test("Profile photos upload on change and download on another device")
    func profileImages() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let profile = try #require(harness.context.currentProfile())
        profile.photoData = TestImage.jpeg
        profile.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()
        #expect(await harness.server.liveRecords().profile?.photoURL != nil)

        // A second device signed in to the same account.
        let other = try MetlyModelContainer.make(inMemory: true)
        let otherEngine = SyncEngine(container: other, api: harness.server, network: harness.network,
                                     state: SyncStateStore(defaults: UserDefaults(suiteName: "metly.tests.\(UUID().uuidString)")!),
                                     observeChanges: false)
        await otherEngine.syncNow()
        #expect(other.mainContext.currentProfile()?.photoData == TestImage.jpeg)

        // Removing the photo propagates too.
        profile.photoData = nil
        profile.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()
        await otherEngine.syncNow()
        #expect(other.mainContext.currentProfile()?.photoData == nil)
    }
}
