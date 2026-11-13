import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import Testing
@testable import MetlyData

@MainActor
@Suite("DTO ⇄ model mapping")
struct MappingTests {
    @Test func cardRoundTrip() throws {
        let card = Card(name: "Work", slug: "aziza-w7k2", sortOrder: 3,
                        design: CardDesign(template: .split, palette: .sand, visibleFields: [.email]))
        card.publishState = .published
        card.stats = CardStats(views: 9)
        let dto = card.dto
        #expect(dto.slug == "aziza-w7k2")
        #expect(dto.url == Brand.cardURL(slug: "aziza-w7k2"))
        let copy = Card(dto: dto)
        #expect(copy.id == card.id)
        #expect(copy.design == card.design)
        #expect(copy.publishState == .published)
        #expect(copy.stats.views == 9)
        #expect(Card(name: "Draft").dto.slug == nil)
    }

    @Test("Server-owned fields only touch slug/publish/stats")
    func cardServerOwned() {
        let card = Card(name: "Mine")
        var dto = card.dto
        dto.name = "Server name"
        dto.slug = "aziza-zz11"
        dto.publishState = .published
        card.applyServerOwned(dto)
        #expect(card.name == "Mine")
        #expect(card.slug == "aziza-zz11")
        #expect(card.publishState == .published)
    }

    @Test("Connections and follow-ups resolve relationships by id")
    func relationships() throws {
        let container = try MetlyModelContainer.make(inMemory: true)
        let context = container.mainContext
        let account = MockSeed.demoAccount()
        let event = Event(dto: account.events[0])
        context.insert(event)
        let connection = Connection(dto: account.connections[0], in: context)
        let followUp = FollowUp(dto: account.followUps[0], in: context)
        try context.save()

        #expect(connection.event?.id == MockSeed.eventID)
        #expect(followUp.connection?.id == connection.id)
        #expect(connection.dto.eventID == MockSeed.eventID)
        #expect(followUp.dto.connectionID == connection.id)
        #expect(connection.dto.theirCard == account.connections[0].theirCard)
        #expect(connection.dto.note == account.connections[0].note)
        withExtendedLifetime(container) {}   // a released container makes SwiftData trap
    }

    @Test func connectRequestRoundTrip() {
        let dto = MockSeed.demoAccount().connectRequests[0]
        let request = ConnectRequest(dto: dto)
        #expect(request.peerName == "Bekzod Tursunov")
        #expect(request.peerCard == dto.peer.card)
        #expect(request.dto.peer.userID == dto.peer.userID)
        #expect(request.dto.status == .pending)
    }

    @Test("PreviewSeed uses the mock server's stable ids")
    func previewSeedMatchesMockSeed() throws {
        let container = MetlyModelContainer.preview(.full)
        let context = container.mainContext
        #expect(context.currentProfile()?.id == MockSeed.profileID)
        #expect(context.defaultCard()?.id == PreviewSeed.workCardID)
        let people = try context.fetch(Connection.live)
        #expect(Set(people.map(\.id)) == Set(MockSeed.connectionIDs))
        #expect(people.first?.fullName == "Kamila Yusupova")   // newest first
        #expect(try context.fetch(FollowUp.open).count == 4)
        #expect(context.activeEvent()?.connections.count == 3)
        #expect(try context.fetch(ConnectRequest.pendingIncoming).count == 1)
        #expect(people.allSatisfy { $0.syncState == .synced })

        let emptyContainer = MetlyModelContainer.preview(.empty)
        #expect(try emptyContainer.mainContext.fetch(Card.live).count == 1)
        #expect(try emptyContainer.mainContext.fetch(Connection.live).isEmpty)
        withExtendedLifetime((container, emptyContainer)) {}
    }

    @Test("A server connection re-keys the optimistic local one for the same Nameshake user")
    func optimisticConnectionIsRekeyed() throws {
        let container = try MetlyModelContainer.make(inMemory: true)
        let context = container.mainContext
        let peerID = UUID()
        let local = Connection(fullName: "Bekzod", source: .connectRequest)
        local.remoteUserID = peerID
        local.note = "Met at the coffee line"
        context.insert(local)
        let followUp = FollowUp(channel: .telegram, dueAt: .now, connection: local)
        context.insert(followUp)

        let server = ConnectionDTO(id: UUID(), remoteUserID: peerID, fullName: "Bekzod Tursunov", source: .connectRequest,
                                   context: MeetingContext(), createdAt: .now, updatedAt: .now)
        let merged = context.upsert(server)
        try context.save()
        #expect(merged === local)
        #expect(local.id == server.id)
        #expect(followUp.connection?.id == server.id)
        #expect(try context.fetch(FetchDescriptor<Connection>()).count == 1)
        withExtendedLifetime(container) {}
    }

    @Test("Wipe is idempotent")
    func wipeTwice() throws {
        let container = MetlyModelContainer.preview(.full)
        try MetlyModelContainer.wipe(container.mainContext)
        try MetlyModelContainer.wipe(container.mainContext)
        #expect(try container.mainContext.fetch(FetchDescriptor<Connection>()).isEmpty)
        #expect(container.mainContext.currentProfile() == nil)
    }
}
