import Foundation
import MetlyCore
import Testing
@testable import MetlyNetworking

@Suite("Labelled phones (wire + mock)", .timeLimit(.minutes(1)))
struct LabeledPhoneTests {
    let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)
    let work = LabeledPhone(id: UUID(), label: .work, value: "+998 71 200 00 00", privacy: .public)
    let home = LabeledPhone(id: UUID(), label: .home, value: "+998 71 300 00 00", privacy: .connections)

    private func roundTrip<T: Codable>(_ value: T) throws -> T {
        try MetlyJSON.makeDecoder().decode(T.self, from: MetlyJSON.makeEncoder().encode(value))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try MetlyJSON.makeDecoder().decode(type, from: Data(json.utf8))
    }

    private func profile(phones: [LabeledPhone], label: PhoneLabel = .work) -> ProfileDTO {
        ProfileDTO(id: UUID(), fullName: "Aziza", jobTitle: "", company: "", contactFields: ContactField.defaults,
                   phoneLabel: label, additionalPhones: phones, defaultCardID: nil, linksPaused: false,
                   notificationPrefs: NotificationPrefs(), privacySettings: PrivacySettings(), isSetupComplete: true,
                   createdAt: fixedDate, updatedAt: fixedDate)
    }

    // MARK: Wire

    @Test("Profile and Connection round-trip phoneLabel + additionalPhones as {id,label,value,privacy}")
    func roundTrips() throws {
        let profile = profile(phones: [work, home])
        #expect(try roundTrip(profile) == profile)
        let json = String(decoding: try MetlyJSON.makeEncoder().encode(profile), as: UTF8.self)
        #expect(json.contains(#""phoneLabel":"work""#))
        #expect(json.contains(#""additionalPhones":[{"id":"#))
        #expect(json.contains(#""label":"home","privacy":"connections","value":"+998 71 300 00 00""#))

        let connection = ConnectionDTO(id: UUID(), fullName: "Kamila", phone: "+998 90 555 12 34", phoneLabel: .home,
                                       additionalPhones: [work], source: .nearby, context: MeetingContext(metAt: fixedDate),
                                       createdAt: fixedDate, updatedAt: fixedDate)
        #expect(try roundTrip(connection) == connection)
    }

    @Test("Payloads from before labelled phones decode with defaults (Mobile, no extra phones)")
    func oldPayloadsDecode() throws {
        let profile = try decode(ProfileDTO.self, """
            {"id":"6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a11","fullName":"Aziza","jobTitle":"","company":"",
             "contactFields":[{"kind":"phone","value":"+998 90 123 45 67","privacy":"public"}],"linksPaused":false,
             "notificationPrefs":{"followUpReminders":true,"eventSummary":true,"delivery":"push","telegramLinked":false,
             "connectRequests":true,"cardSaved":true,"weeklySummary":false,"productNews":false},
             "privacySettings":{"findByEmail":true,"showInNearby":true,"shareAnalytics":true},"isSetupComplete":true,
             "createdAt":"2026-09-26T10:00:00Z","updatedAt":"2026-09-26T10:00:00.000Z"}
            """)
        #expect(profile.phoneLabel == .mobile)
        #expect(profile.additionalPhones.isEmpty)

        let connection = try decode(ConnectionDTO.self, """
            {"id":"6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a12","fullName":"Kamila","jobTitle":"","company":"","phone":"+998",
             "email":"","telegram":"","website":"","linkedin":"","source":"nearby","context":{"metAt":"2026-09-26T10:00:00Z"},
             "previousMeetings":[],"note":"","tags":[],"isMerged":false,"isPendingMerge":false,"isBlocked":false,
             "phoneLabel":null,"additionalPhones":null,
             "createdAt":"2026-09-26T10:00:00Z","updatedAt":"2026-09-26T10:00:00Z"}
            """)
        #expect(connection.phoneLabel == .mobile)
        #expect(connection.additionalPhones.isEmpty)

        let card = try decode(PublicCardDTO.self, #"{"slug":"kamila-x1y2","status":"available","fields":[]}"#)
        #expect(card.phoneLabel == .mobile)
        #expect(card.additionalPhones.isEmpty)
    }

    @Test("Unknown labels read as Other, missing privacy as Connections; elements without a value are dropped")
    func lenientElements() throws {
        let card = try decode(PublicCardDTO.self, """
            {"slug":"kamila-x1y2","status":"available","phoneLabel":"pager","additionalPhones":[
              {"id":"6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a13","label":"fax","value":"+998 71 1"},
              {"label":"work","value":"+998 71 2","privacy":"public"},
              {"id":"6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a14","label":"home"},
              42]}
            """)
        #expect(card.phoneLabel == .other)
        #expect(card.additionalPhones.map(\.label) == [.other, .work])
        #expect(card.additionalPhones.map(\.privacy) == [.connections, .public])
        #expect(card.additionalPhones[0].id == UUID(uuidString: "6f1c2c33-0f4b-4b44-9d3c-1a6a2e0e8a13"))
    }

    @Test func publicCardFaceContentCarriesExtraPhones() throws {
        let card = PublicCardDTO(slug: "kamila-x1y2", status: .available,
                                 owner: PublicOwnerDTO(userID: nil, fullName: "Kamila Yusupova", firstName: "Kamila", jobTitle: "", company: ""),
                                 fields: [ContactField(kind: .phone, value: "+998 90 555 12 34", privacy: .public)],
                                 phoneLabel: .home, additionalPhones: [work, LabeledPhone(value: " ")])
        let content = try #require(card.faceContent)
        #expect(content.phoneLabel == .home)
        #expect(content.additionalPhones == [work])
        #expect(card.snapshot?.fields.count == 1)   // the frozen snapshot is unchanged
        #expect(PublicCardDTO(slug: "x", status: .paused).faceContent == nil)
    }

    // MARK: Merge rules

    @Test("Merging fills an empty phone, adopts the label of the same number and appends new numbers once")
    func mergeRules() {
        var phone = ""
        var label = PhoneLabel.mobile
        var extra: [LabeledPhone] = []
        #expect(PhoneMerge.merge(phone: &phone, label: &label, additional: &extra,
                                 incomingPhone: "+998 90 555 12 34", incomingLabel: .work, incomingAdditional: [home]))
        #expect(phone == "+998 90 555 12 34" && label == .work)
        #expect(extra.map(\.value) == [home.value])
        #expect(extra.allSatisfy { $0.privacy == .connections })

        // Same numbers again (formatted differently): only the label follows, nothing is duplicated.
        #expect(PhoneMerge.merge(phone: &phone, label: &label, additional: &extra,
                                 incomingPhone: "998905551234", incomingLabel: .mobile, incomingAdditional: [home]))
        #expect(label == .mobile && extra.count == 1)
        #expect(!PhoneMerge.merge(phone: &phone, label: &label, additional: &extra,
                                  incomingPhone: "+998 90 555-12-34", incomingLabel: .mobile, incomingAdditional: [home]))

        // A different primary becomes an extra; the list never exceeds the limit.
        let many = (0..<8).map { LabeledPhone(label: .other, value: "+1 555 000 00 0\($0)") }
        PhoneMerge.merge(phone: &phone, label: &label, additional: &extra,
                         incomingPhone: "+998 93 000 00 00", incomingLabel: .home, incomingAdditional: many)
        #expect(phone == "+998 90 555 12 34")
        #expect(extra.count == LabeledPhone.maxAdditional)
        #expect(extra[1].value == "+998 93 000 00 00" && extra[1].label == .home && !extra[1].isPrimary)

        // No primary there: the first extra is promoted.
        var empty = ""
        var emptyLabel = PhoneLabel.mobile
        var none: [LabeledPhone] = []
        PhoneMerge.merge(phone: &empty, label: &emptyLabel, additional: &none, incomingPhone: "", incomingLabel: .mobile,
                         incomingAdditional: [work, home])
        #expect(empty == work.value && emptyLabel == .work && none.map(\.value) == [home.value])
    }

    @Test func validation() {
        #expect(LabeledPhone.validationProblem([work, home]) == nil)
        #expect(LabeledPhone.validationProblem(Array(repeating: work, count: 6)) != nil)
        #expect(LabeledPhone.validationProblem([LabeledPhone(value: String(repeating: "1", count: 41))]) != nil)
    }

    // MARK: Mock server

    @Test("Public profile: Public extra phones for everyone, Connections ones only for mutual connections")
    func mockPublicFiltering() async throws {
        let homeOnly = LabeledPhone(id: UUID(), label: .home, value: "+998 71 999 99 99", privacy: .connections)
        var demo = MockSeed.demoAccount()
        demo.profile?.additionalPhones = [MockSeed.ownerWorkPhone, homeOnly,
                                          LabeledPhone(label: .other, value: "+998 71 000 00 01", privacy: .private)]
        let connected = MockMetlyServer(seed: .account(demo), configuration: .instant)
        let kamila = try await connected.publicProfile(slug: "kamila-x1y2")
        #expect(kamila.viewer?.isConnected == true)
        #expect(kamila.additionalPhones == [MockSeed.kamilaWorkPhone])

        // Not connected (no demo connections): her Connections-level mobile is hidden, the Work line isn't.
        let stranger = MockMetlyServer(seed: .account(demo.minimal), configuration: .instant)
        let unconnected = try await stranger.publicProfile(slug: "kamila-x1y2")
        #expect(unconnected.viewer?.isConnected == false)
        #expect(!unconnected.fields.contains { $0.kind == .phone })
        #expect(unconnected.additionalPhones == [MockSeed.kamilaWorkPhone])
        #expect(unconnected.faceContent?.additionalPhones.first?.label == .work)

        // Own card: Public + Connections, never Private.
        let own = try await connected.publicProfile(slug: "aziza-w7k2")
        #expect(own.additionalPhones.map(\.id) == [MockSeed.ownerWorkPhone.id, homeOnly.id])
    }

    @Test("Accepting a connect copies the peer's labelled phones onto the new connection")
    func mockAcceptCopiesPhones() async throws {
        let server = MockMetlyServer(seed: .account(MockSeed.demoAccount().minimal), configuration: .instant)
        let stream = await server.connectEvents()
        let request = try await server.sendRequest(SendConnectRequest(toSlug: "kamila-x1y2", cardID: MockSeed.workCardID, method: .scan))
        var connection: ConnectionDTO?
        for await event in stream {
            if case .requestUpdated(let updated, let accepted) = event, updated.id == request.id {
                connection = accepted
                break
            }
        }
        let kamila = try #require(connection)
        #expect(kamila.phone == "+998 90 555 12 34")
        #expect(kamila.phoneLabel == .mobile)
        #expect(kamila.additionalPhones.map(\.value) == [MockSeed.kamilaWorkPhone.value])
        #expect(kamila.additionalPhones.first?.label == .work)
        #expect(kamila.theirCard?.fields.contains { $0.kind == .phone } == false)   // the snapshot stays Public-only
    }

    @Test("Sync push keeps phones, rejects more than 5 or over-long numbers (validation_failed)")
    func mockValidation() async throws {
        let server = MockMetlyServer(seed: .demo, configuration: .instant)
        var profile = try #require(MockSeed.demoAccount().profile)
        profile.phoneLabel = .home
        profile.updatedAt = .now
        let applied = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(profile: profile)))
        #expect(applied.results.first?.status == .applied)
        #expect(applied.records.profile?.phoneLabel == .home)
        #expect(applied.records.profile?.additionalPhones == [MockSeed.ownerWorkPhone])

        profile.additionalPhones = Array(repeating: MockSeed.ownerWorkPhone, count: 6)
        profile.updatedAt = .now.addingTimeInterval(1)
        let rejected = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(profile: profile)))
        #expect(rejected.results.first?.status == .rejected)
        #expect(rejected.results.first?.error?.knownCode == .validationFailed)

        var connection = try #require(MockSeed.demoAccount().connections.first)
        connection.additionalPhones = [LabeledPhone(value: String(repeating: "9", count: 41))]
        connection.updatedAt = .now
        await #expect(throws: APIError.self) { _ = try await server.upsertConnection(connection) }
        #expect(await server.liveRecords().connections.first { $0.id == connection.id }?.additionalPhones.count == 1)
    }
}
