import Foundation
import MetlyCore
import Testing
@testable import MetlyNetworking

@Suite("Wire format")
struct JSONCodingTests {
    let fixedDate = Date(timeIntervalSince1970: 1_790_000_000)   // whole seconds → exact round trips

    private func roundTrip<T: Codable & Equatable>(_ value: T) throws -> T {
        let data = try MetlyJSON.makeEncoder().encode(value)
        return try MetlyJSON.makeDecoder().decode(T.self, from: data)
    }

    private func json(_ value: some Encodable) throws -> String {
        String(decoding: try MetlyJSON.makeEncoder().encode(value), as: UTF8.self)
    }

    @Test("ID / URL suffixes travel as Id / Url")
    func keySuffixes() throws {
        let connection = ConnectionDTO(id: UUID(), remoteUserID: UUID(), fullName: "Kamila", avatarURL: URL(string: "https://a.tanishly.app/x.jpg"),
                                       mySharedCardID: UUID(), source: .nearby, context: MeetingContext(eventID: UUID(), metAt: fixedDate),
                                       eventID: UUID(), createdAt: fixedDate, updatedAt: fixedDate)
        let text = try json(connection)
        #expect(text.contains("\"remoteUserId\""))
        #expect(text.contains("\"mySharedCardId\""))
        #expect(text.contains("\"avatarUrl\""))
        #expect(text.contains("\"eventId\""))
        #expect(!text.contains("ID\""))
        #expect(text.contains("\"id\""))
        #expect(try roundTrip(connection) == connection)
    }

    @Test func suffixMappingLeavesOrdinaryWordsAlone() {
        struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ value: String) { stringValue = value }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }
        #expect(MetlyJSON.wireName(for: Key("cardIDs")) == "cardIds")
        #expect(MetlyJSON.wireName(for: Key("id")) == "id")
        #expect(MetlyJSON.swiftName(for: Key("cardIds")) == "cardIDs")
        #expect(MetlyJSON.swiftName(for: Key("photoUrl")) == "photoURL")
        #expect(MetlyJSON.swiftName(for: Key("void")) == "void")
        #expect(MetlyJSON.swiftName(for: Key("AId")) == "AId")
    }

    @Test("Dates decode with and without fractional seconds")
    func dates() throws {
        struct Box: Codable { var at: Date }
        let plain = try MetlyJSON.makeDecoder().decode(Box.self, from: Data(#"{"at":"2026-09-26T10:00:00Z"}"#.utf8))
        let fractional = try MetlyJSON.makeDecoder().decode(Box.self, from: Data(#"{"at":"2026-09-26T10:00:00.250Z"}"#.utf8))
        #expect(abs(fractional.at.timeIntervalSince(plain.at) - 0.25) < 0.001)
        #expect(try json(Box(at: plain.at)).contains("2026-09-26T10:00:00.000Z"))
        #expect(throws: DecodingError.self) {
            try MetlyJSON.makeDecoder().decode(Box.self, from: Data(#"{"at":"yesterday"}"#.utf8))
        }
    }

    @Test func recordRoundTrips() throws {
        let profile = ProfileDTO(id: UUID(), fullName: "Aziza Karimova", jobTitle: "Designer", company: "Tezkor",
                                 photoURL: URL(string: "https://assets.tanishly.app/p.jpg"), contactFields: ContactField.defaults,
                                 defaultCardID: UUID(), linksPaused: true, notificationPrefs: NotificationPrefs(),
                                 privacySettings: PrivacySettings(), isSetupComplete: true, createdAt: fixedDate, updatedAt: fixedDate)
        #expect(try roundTrip(profile) == profile)

        let card = CardDTO(id: UUID(), name: "Work", slug: "aziza-w7k2", url: Brand.cardURL(slug: "aziza-w7k2"), sortOrder: 1,
                           design: CardDesign(template: .editorial, palette: .ocean, visibleFields: [.email, .phone]),
                           publishState: .published, isReadOnly: true, isPaused: false, stats: CardStats(views: 3),
                           createdAt: fixedDate, updatedAt: fixedDate, deletedAt: fixedDate)
        #expect(try roundTrip(card) == card)

        let followUp = FollowUpDTO(id: UUID(), connectionID: UUID(), title: "Send deck", channel: .email, dueAt: fixedDate,
                                   isDone: true, completedAt: fixedDate, createdAt: fixedDate, updatedAt: fixedDate)
        #expect(try roundTrip(followUp) == followUp)

        let event = EventDTO(id: UUID(), name: "Tech Week", place: "Hyatt", city: "Tashkent", startDate: fixedDate, endDate: fixedDate,
                             cardID: nil, status: .ended, calendarEventIdentifier: "ek-1", endedAt: fixedDate,
                             createdAt: fixedDate, updatedAt: fixedDate)
        #expect(try roundTrip(event) == event)

        let request = ConnectRequestDTO(id: UUID(), direction: .incoming,
                                        peer: PeerSummaryDTO(userID: UUID(), fullName: "Bekzod", card: MockSeed.peers[2].card),
                                        myCardID: nil, method: .tapPhones, status: .pending, eventName: "Tech Week",
                                        createdAt: fixedDate, expiresAt: fixedDate, updatedAt: fixedDate)
        #expect(try roundTrip(request) == request)
    }

    @Test func syncPayloadsRoundTrip() throws {
        let account = MockSeed.demoAccount(now: fixedDate)
        let changes = SyncChanges(profile: account.profile, cards: account.cards, events: account.events,
                                  connections: account.connections, followUps: account.followUps,
                                  connectRequests: account.connectRequests,
                                  tombstones: [TombstoneDTO(type: .card, id: UUID(), deletedAt: fixedDate)])
        let pull = SyncPullResponse(changes: changes, cursor: "c_1", hasMore: true, serverTime: fixedDate, entitlement: .free)
        let decoded = try roundTrip(pull)
        #expect(decoded.changes.connections.count == 6)
        #expect(decoded.cursor == "c_1")
        #expect(decoded.entitlement?.limits.maxCards == 2)
        // Sub-millisecond precision is dropped on the wire; compare what matters.
        #expect(decoded.changes.connections.map(\.id) == changes.connections.map(\.id))
        #expect(decoded.changes.tombstones == changes.tombstones)

        let push = SyncPushRequest(deviceID: "dev-1", changes: SyncChanges(cards: [account.cards[0]]))
        #expect(try roundTrip(push).changes.cards.first?.slug == "aziza-w7k2")
    }

    @Test("Omitted change arrays decode as empty")
    func sparseChanges() throws {
        let changes = try MetlyJSON.makeDecoder().decode(SyncChanges.self, from: Data(#"{"cards":[]}"#.utf8))
        #expect(changes.isEmpty)
        #expect(changes.profile == nil)
    }

    @Test func problemAndErrorMapping() throws {
        let body = Data(#"{"code":"plan_limit_reached","message":"Free plan includes 2 cards.","requestId":"req_1","details":{"limit":"2"}}"#.utf8)
        let problem = try MetlyJSON.makeDecoder().decode(APIProblem.self, from: body)
        #expect(problem.knownCode == .planLimitReached)
        #expect(problem.requestID == "req_1")
        #expect(problem.details?["limit"] == "2")
        let error = APIError.server(status: 403, problem: problem)
        #expect(error.isPlanLimit)
        #expect(!error.isTransient)
        #expect(APIError(URLError(.notConnectedToInternet)) == .offline)
        #expect(APIError(URLError(.timedOut)) == .timedOut)
        #expect(APIError(CancellationError()) == .cancelled)
    }

    @Test("Card face options travel inside design, only when not the default")
    func cardFaceOptions() throws {
        let plain = CardDTO(id: UUID(), name: "Work", sortOrder: 0, design: CardDesign(), createdAt: fixedDate, updatedAt: fixedDate)
        let plainJSON = try json(plain)
        #expect(!plainJSON.contains("showJobTitle") && !plainJSON.contains("logoStyle"))
        #expect(try roundTrip(plain).faceOptions == CardFaceOptions())

        var hidden = plain
        hidden.faceOptions = CardFaceOptions(showJobTitle: false, showCompany: true, logoStyle: .mono)
        let hiddenJSON = try json(hidden)
        #expect(hiddenJSON.contains(#""showJobTitle":false"#) && hiddenJSON.contains(#""logoStyle":"mono""#))
        #expect(!hiddenJSON.contains("showCompany"))
        #expect(try roundTrip(hidden) == hidden)
    }

    @Test func unavailablePublicCardHasNoPersonalData() throws {
        let card = try MetlyJSON.makeDecoder().decode(PublicCardDTO.self, from: Data(#"{"slug":"lola-p0z3","status":"paused"}"#.utf8))
        #expect(card.status == .paused)
        #expect(card.fields.isEmpty)
        #expect(card.snapshot == nil)
    }

    @Test("Realtime envelopes decode per type; unknown types are ignored")
    func realtimeMessages() throws {
        let request = MockSeed.demoAccount(now: fixedDate).connectRequests[0]
        let connection = MockSeed.demoAccount(now: fixedDate).connections[0]
        for event in [ConnectEvent.requestReceived(request), .requestUpdated(request, connection: connection), .syncAvailable] {
            let decoded = try roundTrip(RealtimeMessage(event: event, sentAt: fixedDate))
            switch (decoded.event, event) {
            case (.requestReceived(let a), .requestReceived(let b)): #expect(a.id == b.id)
            case (.requestUpdated(let a, let c), .requestUpdated(let b, _)): #expect(a.id == b.id && c?.id == connection.id)
            case (.syncAvailable, .syncAvailable): break
            default: Issue.record("Mismatched event \(String(describing: decoded.event))")
            }
        }
        let unknown = try MetlyJSON.makeDecoder().decode(RealtimeMessage.self, from: Data(#"{"type":"future.thing","data":{"x":1}}"#.utf8))
        #expect(unknown.event == nil)
        let ping = try MetlyJSON.makeDecoder().decode(RealtimeMessage.self, from: Data(#"{"type":"ping"}"#.utf8))
        #expect(ping.type == "ping" && ping.event == nil)
    }

    @Test func baseURLResolution() {
        #expect(MetlyNetworking.parseBaseURL("$(METLY_API_BASE_URL)") == nil)
        #expect(MetlyNetworking.parseBaseURL("   ") == nil)
        #expect(MetlyNetworking.parseBaseURL(nil) == nil)
        #expect(MetlyNetworking.parseBaseURL("ftp://x") == nil)
        #expect(MetlyNetworking.parseBaseURL("https://api.tanishly.app")?.host() == "api.tanishly.app")
        #expect(MetlyNetworking.configuredBaseURL(bundle: .main, defaults: UserDefaults(suiteName: UUID().uuidString)!,
                                                  arguments: ["-MetlyUseMockServer"]) == nil)
    }
}
