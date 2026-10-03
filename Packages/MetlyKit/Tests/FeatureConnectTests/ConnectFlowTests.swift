import Foundation
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
import Testing
@testable import FeatureConnect

/// End-to-end CONNECT flows against the mock server (instant timers) and the demo transport.
@MainActor
struct ConnectFlowTests {
    private struct Harness {
        let model: ConnectModel
        let client: MetlyClient
        let router: AppRouter
        let context: ModelContext
    }

    private func harness(online: Bool = true, prepare: (ModelContext) -> Void = { _ in }) throws -> Harness {
        let container = try makeContainer(.full)
        let context = container.mainContext
        prepare(context)
        try context.save()
        let client = makeClient(container: container, online: online)
        client.startRealtime()
        let router = AppRouter(phase: .main)
        router.present(.connect(cardID: nil))
        let model = ConnectModel { _ in
            DemoNearbyTransport(tokens: ["mock-peer-kamila", "mock-peer-nodira"],
                                firstDelay: .milliseconds(5), interval: .milliseconds(5))
        }
        model.attach(client: client, modelContext: context, router: router, requestedCardID: nil)
        return Harness(model: model, client: client, router: router, context: context)
    }

    // MARK: Nearby

    @Test func discoversResolvesAndConnects() async throws {
        let h = try harness()
        let discovery = Task { await h.model.runDiscovery() }

        try await waitUntil("two people listed") { h.model.peers.people.count == 2 }
        #expect(h.model.availability == .active)
        #expect(h.model.selectedCardID == MockSeed.workCardID)   // the active event's card

        let kamila = try #require(h.model.peers.people.first { $0.firstName == "Kamila" })
        h.model.connect(to: kamila)
        #expect(h.model.machine.waitingPeer?.userID == kamila.userID)

        try await waitUntil("connected") { h.model.machine.connectedID != nil }
        let connectionID = try #require(h.model.machine.connectedID)
        #expect(h.router.presentations == [.cover(.connected(connectionID: connectionID))])
        #expect(h.context.record(Connection.self, id: connectionID)?.remoteUserID == kamila.userID)

        discovery.cancel()
        await discovery.value
    }

    @Test func unansweredRequestReadsNoResponse() async throws {
        let h = try harness()
        let discovery = Task { await h.model.runDiscovery() }

        try await waitUntil("Nodira listed") { h.model.peers.people.contains { $0.firstName == "Nodira" } }
        let nodira = try #require(h.model.peers.people.first { $0.firstName == "Nodira" })
        h.model.connect(to: nodira)

        try await waitUntil("no response", timeout: .seconds(8)) { h.model.machine.notice != nil }
        #expect(h.model.machine.notice == .noResponse(firstName: "Nodira"))
        #expect(h.model.machine.phase == .discovering)
        #expect(h.router.presentations == [.cover(.connect(cardID: nil))])

        discovery.cancel()
        await discovery.value
    }

    @Test func cancellingWithdrawsAndKeepsBrowsing() async throws {
        let h = try harness()
        let discovery = Task { await h.model.runDiscovery() }

        try await waitUntil("Nodira listed") { h.model.peers.people.contains { $0.firstName == "Nodira" } }
        let nodira = try #require(h.model.peers.people.first { $0.firstName == "Nodira" })
        h.model.connect(to: nodira)
        h.model.cancelRequest()
        #expect(h.model.machine.phase == .discovering)
        #expect(h.model.machine.notice == nil)

        discovery.cancel()
        await discovery.value
        #expect(h.model.machine.phase == .idle)
        #expect(h.model.peers.isEmpty)
    }

    @Test func blockedPeopleAreNotListed() async throws {
        let h = try harness { context in
            let kamila = context.record(Connection.self, id: PreviewSeed.firstConnectionID)
            kamila?.isBlocked = true
        }
        let discovery = Task { await h.model.runDiscovery() }

        try await waitUntil("Nodira listed") { !h.model.peers.isEmpty }
        try await Task.sleep(for: .milliseconds(400))   // let any further resolve land
        #expect(h.model.peers.people.map(\.firstName) == ["Nodira"])

        discovery.cancel()
        await discovery.value
    }

    @Test func hiddenFromNearbyDoesNotAdvertise() async throws {
        let h = try harness { context in
            context.currentProfile()?.privacySettings.showInNearby = false
        }
        await h.model.runDiscovery()
        #expect(h.model.availability == .hiddenFromNearby)
        #expect(h.model.machine.phase == .idle)

        let generation = h.model.discoveryGeneration
        h.model.turnOnShowInNearby()
        #expect(h.context.currentProfile()?.privacySettings.showInNearby == true)
        #expect(h.context.currentProfile()?.syncState == .pendingUpsert)
        #expect(h.model.discoveryGeneration == generation + 1)
    }

    @Test func offlineSessionShowsOfflineState() async throws {
        let h = try harness(online: false)
        await h.model.runDiscovery()
        #expect(h.model.availability == .offline)
    }

    // MARK: Incoming

    @Test func acceptingIncomingLandsOnConnected() async throws {
        let h = try harness()
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        h.model.present(request)
        #expect(h.model.incomingRequest?.id == request.id)

        h.model.acceptIncoming()
        #expect(h.model.machine.isAccepting)
        try await waitUntil("connected") { h.model.machine.connectedID != nil }

        let connectionID = try #require(h.model.machine.connectedID)
        #expect(h.router.presentations == [.cover(.connected(connectionID: connectionID))])
        let connection = try #require(h.context.record(Connection.self, id: connectionID))
        #expect(connection.remoteUserID == request.peerUserID)
        #expect(h.model.incomingRequest == nil)
    }

    @Test func offlineAcceptStillLandsOnConnected() async throws {
        let h = try harness(online: false)
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        h.model.present(request)
        h.model.acceptIncoming()
        try await waitUntil("connected") { h.model.machine.connectedID != nil }

        let connectionID = try #require(h.model.machine.connectedID)
        let connection = try #require(h.context.record(Connection.self, id: connectionID))
        #expect(connection.remoteUserID == request.peerUserID)
        #expect(connection.mySharedCardID == MockSeed.workCardID)
        #expect(connection.theirCard == request.peerCard)
        #expect(connection.syncState == .pendingUpsert)
        #expect(connection.event?.id == MockSeed.eventID)
        #expect(request.status == .accepted)
    }

    @Test func decliningShowsToastAndKeepsBrowsing() async throws {
        let h = try harness()
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        h.model.present(request)
        h.model.declineIncoming()
        #expect(h.model.incomingRequest == nil)
        #expect(h.router.toast?.message == "Request Declined")
        #expect(h.router.presentations == [.cover(.connect(cardID: nil))])
    }

    @Test func requestsFromBlockedPeopleAreIgnored() async throws {
        let h = try harness()
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        let blocked = Connection(fullName: request.peerName, source: .nearby)
        blocked.remoteUserID = request.peerUserID
        blocked.isBlocked = true
        h.context.insert(blocked)
        try h.context.save()

        let model = ConnectModel()
        model.attach(client: h.client, modelContext: h.context, router: h.router, requestedCardID: nil)
        model.present(request)
        #expect(model.incomingRequest == nil)
    }
}
