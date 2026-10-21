import Foundation
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
import Testing
@testable import FeatureConnect

/// Records whether anything is still being advertised / browsed.
@MainActor
final class SpyTransport: NearbyTransport {
    private(set) var isRunning = false
    private(set) var startCount = 0
    private var continuation: AsyncStream<NearbyTransportEvent>.Continuation?

    var supportsLinks: Bool { false }

    func start(advertising token: String) -> AsyncStream<NearbyTransportEvent> {
        stop()
        startCount += 1
        isRunning = true
        let (stream, continuation) = AsyncStream.makeStream(of: NearbyTransportEvent.self)
        self.continuation = continuation
        continuation.yield(.state(.searching))
        return stream
    }

    func stop() {
        isRunning = false
        continuation?.finish()
        continuation = nil
    }

    func send(_ data: Data, to peer: NearbyPeerHandle) {}
}

@MainActor
struct ConnectRegressionTests {
    /// Regression: "Try Again" starts a new discovery run before the old one has cleaned up. The old run
    /// skipped `transport.stop()` (it was superseded) and the new run failed before restarting the transport,
    /// so MultipeerConnectivity kept advertising and browsing — even after CONNECT closed.
    @Test func aFailedRestartDoesNotLeaveTheOldTransportAdvertising() async throws {
        let container = try makeContainer(.full)
        let client = makeClient(container: container)
        let spy = SpyTransport()
        let model = ConnectModel { _ in spy }
        model.attach(client: client, modelContext: container.mainContext, router: AppRouter(phase: .main),
                     requestedCardID: nil)

        let first = Task { await model.runDiscovery() }
        try await waitUntil("advertising") { spy.isRunning && model.availability == .active }

        // SwiftUI's `.task(id:)` starts the new run, then cancels the old one.
        await client.mockServer?.setReachable(false)
        let second = Task { await model.runDiscovery() }
        try await waitUntil("restart began") { model.availability != .active }
        first.cancel()
        await first.value
        await second.value

        #expect(model.availability == .offline)
        #expect(!spy.isRunning)
    }

    @Test func offlineAcceptDuringAnEventNamesTheCityOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(Event(name: "Tashkent Tech Week", place: "Hyatt Regency, Tashkent", city: "Tashkent"))
        let request = ConnectRequest(direction: .incoming, peerUserID: UUID(), peerName: "Bekzod Tursunov", method: .nearby)
        context.insert(request)
        let person = OfflineAccept.connection(for: request, sharing: UUID(), in: context, now: .now)
        #expect(person.context.place == "Hyatt Regency")
        #expect(person.context.city == "Tashkent")
    }

    /// Regression: the peer accepted just as the user tapped Cancel. The server can't withdraw an accepted
    /// request, so both sides were connected — but CONNECT stayed on the Nearby list (the machine's
    /// "accepted after cancel" transition was never fed) while the other phone showed "You're Connected".
    @Test func acceptedJustAfterCancelOpensConnected() async throws {
        let container = try makeContainer(.full)
        let context = container.mainContext
        let client = makeClient(container: container)
        client.startRealtime()
        let router = AppRouter(phase: .main)
        router.present(.connect(cardID: nil))
        let model = ConnectModel { _ in
            DemoNearbyTransport(tokens: ["mock-peer-nodira"], firstDelay: .milliseconds(5), interval: .milliseconds(5))
        }
        model.attach(client: client, modelContext: context, router: router, requestedCardID: nil)
        let discovery = Task { await model.runDiscovery() }

        try await waitUntil("Nodira listed") { !model.peers.isEmpty }
        let nodira = try #require(model.peers.people.first)
        model.connect(to: nodira)
        let outgoing = ConnectRequestDirection.outgoing.rawValue
        let sent = FetchDescriptor<ConnectRequest>(predicate: #Predicate { $0.directionRaw == outgoing })
        try await waitUntil("request sent") { ((try? context.fetch(sent)) ?? []).contains { $0.peerUserID == nodira.userID } }
        let request = try #require(try context.fetch(sent).first { $0.peerUserID == nodira.userID })

        model.cancelRequest()
        #expect(model.machine.phase == .discovering)

        // Their accept crossed our cancel; the realtime update arrives afterwards.
        let connection = Connection(fullName: "Nodira Azimova", source: .nearby)
        connection.remoteUserID = nodira.userID
        context.insert(connection)
        var answer = request.dto
        answer.status = .accepted
        model.withdrawnRequestUpdated(answer, connection: nil)

        #expect(model.machine.connectedID == connection.id)
        #expect(router.presentations == [.cover(.connected(connectionID: connection.id))])

        discovery.cancel()
        await discovery.value
    }

    @Test func updatesForRequestsTheUserDidNotCancelAreIgnored() throws {
        let container = try makeContainer(.full)
        let client = makeClient(container: container)
        let router = AppRouter(phase: .main)
        let model = ConnectModel()
        model.attach(client: client, modelContext: container.mainContext, router: router, requestedCardID: nil)
        let request = try #require(try container.mainContext.fetch(ConnectRequest.pendingIncoming).first)
        var answer = request.dto
        answer.status = .accepted
        model.withdrawnRequestUpdated(answer, connection: nil)
        #expect(model.machine.connectedID == nil)
        #expect(router.presentations.isEmpty)
    }
}
