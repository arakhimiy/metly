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
        profile.setField(ContactField(kind: .phone, value: "+998 90 100 00 00", privacy: .public))
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
        #expect(copy.allPhones.map(\.value) == ["+998 90 100 00 00", work.value, home.value])
        #expect(copy.contacts == profile.contacts)

        var connectionDTO = MockSeed.demoAccount().connections[0]
        connectionDTO.phoneLabel = .work
        let connection = Connection(dto: connectionDTO, in: context)
        #expect(connection.phoneLabel == .work)
        #expect(connection.additionalPhones.map(\.label) == [.work])
        #expect(connection.dto.phoneLabel == .work)
        #expect(connection.dto.additionalPhones == connectionDTO.additionalPhones)

        // A payload whose legacy fields say one mobile number: the list follows.
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
        let publicPhones = card.faceContent(profile: profile, audience: .public).contacts.filter { $0.kind == .phone }
        #expect(publicPhones.map(\.value) == [MockSeed.ownerWorkPhone.value])   // her mobile is Connections-only
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

    @Test("A rejected push (a number over 40 characters) stays local and isn't retried until edited")
    func tooManyPhonesRejected() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let profile = try #require(harness.context.currentProfile())
        profile.contacts.append(ContactEntry(kind: .phone, label: .home, value: String(repeating: "9", count: 41)))
        profile.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()
        #expect(await harness.server.liveRecords().profile?.additionalPhones == [MockSeed.ownerWorkPhone])
        #expect(profile.additionalPhones.count == 2)
    }

    /// Regression: + Add Contact, then the echo of the last push arrived 2–3 s later and closed the new
    /// (still empty, never sent) row while the user was about to type into it.
    @Test("A row being typed survives the server's copy of the profile")
    func typingRowSurvivesEcho() throws {
        let container = try MetlyModelContainer.make(inMemory: true)
        let profile = Profile(fullName: "Aziza", contactFields: [ContactField(kind: .instagram, value: "@aziza", privacy: .public)])
        container.mainContext.insert(profile)
        let echo = profile.dto
        let typing = try #require(profile.addContact(.telegram))
        profile.apply(echo)
        #expect(profile.contacts.map(\.kind) == [.instagram, .telegram])
        #expect(profile.contacts.last?.id == typing)
    }

    @Test("The contact list round-trips with WhatsApp and Instagram, which older apps never see")
    func contactListRoundTrip() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let profile = try #require(harness.context.currentProfile())
        profile.contacts.append(ContactEntry(kind: .whatsapp, value: "+998 90 123 45 67", privacy: .public))
        profile.contacts.append(ContactEntry(kind: .instagram, value: "@aziza", privacy: .public))
        profile.markChanged()
        try harness.context.save()
        await harness.engine.syncNow()
        let server = try #require(await harness.server.liveRecords().profile)
        let kinds = server.contacts.map(\.kind)
        #expect(Array(kinds.suffix(2)) == [.whatsapp, .instagram])
        let serverKinds = server.contactFields.map(\.kind)
        #expect(serverKinds.allSatisfy { $0.isLegacy })
        let wire = try JSONEncoder().encode(profile.dto)
        let json = try #require(String(data: wire, encoding: .utf8))
        #expect(json.contains("\"contacts\""))
        let fields = try JSONDecoder().decode(LegacyFields.self, from: wire).contactFields
        #expect(fields.allSatisfy { ContactFieldKind.legacy.map(\.rawValue).contains($0.kind) })   // older apps decode these
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

/// What an older app reads from a profile payload.
private struct LegacyFields: Decodable {
    struct Field: Decodable { var kind: String }
    var contactFields: [Field]
}
