import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import Testing
@testable import MetlyData

@MainActor
@Suite("Labelled phones: mapping, sync, client", .timeLimit(.minutes(1)))
struct LabeledPhoneSyncTests {
    let work = LabeledPhone(id: UUID(), label: .work, value: "+998 71 200 00 00", privacy: .public)
    let home = LabeledPhone(id: UUID(), label: .home, value: "+998 71 300 00 00", privacy: .private)

    // MARK: Mapping

    @Test("Profile and Connection map phoneLabel + additionalPhones both ways")
    func mapping() throws {
        let container = try MetlyModelContainer.make(inMemory: true)
        let context = container.mainContext
        let profile = Profile(fullName: "Aziza")
        context.insert(profile)
        profile.phoneLabel = .home
        profile.additionalPhones = [work, home]
        let profileDTO = profile.dto
        #expect(profileDTO.phoneLabel == .home)
        #expect(profileDTO.additionalPhones == [work, home])

        let copy = Profile(id: UUID())
        context.insert(copy)
        copy.apply(profileDTO)
        #expect(copy.phoneLabel == .home)
        #expect(copy.additionalPhones == [work, home])
        #expect(copy.allPhones.map(\.value) == [work.value, home.value])   // primary phone is empty in ContactField.defaults

        var connectionDTO = MockSeed.demoAccount().connections[0]
        connectionDTO.phoneLabel = .work
        let connection = Connection(dto: connectionDTO, in: context)
        #expect(connection.phoneLabel == .work)
        #expect(connection.additionalPhones.map(\.label) == [.work])
        #expect(connection.allPhones.first?.isPrimary == true)
        #expect(connection.dto.phoneLabel == .work)
        #expect(connection.dto.additionalPhones == connectionDTO.additionalPhones)

        // An old payload (no new keys) resets nothing it doesn't know about: defaults.
        connectionDTO.phoneLabel = .mobile
        connectionDTO.additionalPhones = []
        connection.apply(connectionDTO, in: context)
        #expect(connection.phoneLabel == .mobile && connection.additionalPhones.isEmpty)
        withExtendedLifetime(container) {}
    }

    @Test("The demo seed has Aziza's public Work phone and Kamila's office line")
    func previewSeed() throws {
        let container = MetlyModelContainer.preview(.full)
        let context = container.mainContext
        let profile = try #require(context.currentProfile())
        #expect(profile.additionalPhones == [MockSeed.ownerWorkPhone])
        let card = try #require(context.defaultCard())
        #expect(card.faceContent(profile: profile, audience: .public).additionalPhones == [MockSeed.ownerWorkPhone])
        let kamila = try #require(context.record(Connection.self, id: PreviewSeed.firstConnectionID))
        #expect(kamila.allPhones.map(\.label) == [.mobile, .work])
        #expect(kamila.mobilePhone == "+998 90 555 12 34")
        withExtendedLifetime(container) {}
    }

    // MARK: Sync

    @Test("Edited phones are pushed; a newer remote edit of them is pulled")
    func syncRoundTrip() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let profile = try #require(harness.context.currentProfile())
        profile.phoneLabel = .work
        profile.additionalPhones = [work]
        profile.markChanged()
        let sardor = try #require(harness.connection(MockSeed.connectionIDs[1]))
        sardor.phone = "+998 90 111 22 33"
        sardor.additionalPhones = [LabeledPhone(label: .home, value: "+998 71 444 55 66")]
        sardor.markChanged()
        try harness.context.save()

        await harness.engine.syncNow()
        #expect(profile.syncState == .synced && sardor.syncState == .synced)
        let server = await harness.server.liveRecords()
        #expect(server.profile?.phoneLabel == .work)
        #expect(server.profile?.additionalPhones == [work])
        #expect(server.connections.first { $0.id == sardor.id }?.additionalPhones.map(\.value) == ["+998 71 444 55 66"])

        var remote = sardor.dto
        remote.phoneLabel = .home
        remote.additionalPhones = []
        remote.updatedAt = .now.addingTimeInterval(60)
        await harness.server.simulateRemoteChanges(SyncChanges(connections: [remote]))
        await harness.engine.syncNow()
        #expect(sardor.phoneLabel == .home)
        #expect(sardor.additionalPhones.isEmpty)
    }

    @Test("LWW: an older remote version never overwrites unsynced phone edits")
    func dirtyPhonesSurviveOlderPull() throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let kamila = try #require(harness.connection(MockSeed.connectionIDs[0]))
        kamila.additionalPhones.append(LabeledPhone(label: .home, value: "+998 71 777 88 99"))
        kamila.markChanged()

        var remote = kamila.dto
        remote.additionalPhones = []
        remote.phoneLabel = .other
        remote.updatedAt = kamila.updatedAt.addingTimeInterval(-30)
        var applier = SyncApplier(context: harness.context, mode: .pull)
        applier.apply(SyncChanges(connections: [remote]))

        #expect(kamila.additionalPhones.count == 2)
        #expect(kamila.phoneLabel == .mobile)
        #expect(kamila.syncState == .pendingUpsert)
    }

    @Test("A rejected push (more than 5 extra phones) stays local and isn't retried until edited")
    func tooManyPhonesRejected() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let profile = try #require(harness.context.currentProfile())
        profile.additionalPhones = (0..<6).map { LabeledPhone(value: "+998 71 000 00 0\($0)") }
        profile.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()
        #expect(await harness.server.liveRecords().profile?.additionalPhones == [MockSeed.ownerWorkPhone])
        #expect(profile.additionalPhones.count == 6)
    }

    // MARK: Client (connect / SCANNED_CARD)

    @Test("Accepting an incoming request brings the requester's phones; Scan copies them from the public card")
    func clientFlows() async throws {
        var account = MockSeed.demoAccount().minimal
        account.connectRequests = MockSeed.demoAccount().connectRequests
        let harness = try SyncHarness(local: .signedOut, server: .account(account))
        await harness.engine.syncNow()
        let client = MetlyClient(api: harness.server, container: harness.container, mockServer: harness.server)

        let request = try #require(harness.context.record(ConnectRequest.self, id: MockSeed.incomingRequestID))
        let bekzod = try #require(try await client.accept(request, sharing: MockSeed.workCardID))
        #expect(bekzod.additionalPhones.isEmpty)   // Bekzod has no phones: nothing invented

        let card = try await client.publicProfile(slug: "kamila-x1y2")
        #expect(card.additionalPhones == [MockSeed.kamilaWorkPhone])
        let person = Connection(fullName: "Kamila Yusupova", source: .scanQR)
        harness.context.insert(person)
        #expect(person.mergePhones(from: card))
        // Her mobile is Connections-only (not connected yet): the Work line becomes the primary phone.
        #expect(person.phone == MockSeed.kamilaWorkPhone.value)
        #expect(person.phoneLabel == .work)
        #expect(person.additionalPhones.isEmpty)
        #expect(!person.mergePhones(from: card))   // idempotent
    }
}
