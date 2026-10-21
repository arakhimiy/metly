import Foundation
import MetlyCore
import MetlyData
import MetlyNetworking
import SwiftData
import Testing
@testable import FeatureConnect

/// The app-level banner for connect requests that arrive while CONNECT is closed.
@MainActor
struct IncomingRequestBannerTests {
    private struct Harness {
        let model: IncomingRequestBannerModel
        let client: MetlyClient
        let router: AppRouter
        let context: ModelContext
    }

    private func harness(online: Bool = true) throws -> Harness {
        let container = try makeContainer(.full)
        let client = makeClient(container: container, online: online)
        let router = AppRouter(phase: .main)
        let model = IncomingRequestBannerModel()
        model.attach(client: client, modelContext: container.mainContext, router: router)
        return Harness(model: model, client: client, router: router, context: container.mainContext)
    }

    @discardableResult
    private func incoming(_ name: String = "Sardor Rashidov", peer: UUID = UUID(), method: ConnectMethod = .scan,
                          expiresAt: Date? = .now.addingTimeInterval(7 * 86_400), in context: ModelContext) -> ConnectRequest {
        let request = ConnectRequest(direction: .incoming, peerUserID: peer, peerName: name, peerTitle: "CTO",
                                     peerCompany: "Payme", method: method)
        request.expiresAt = expiresAt
        context.insert(request)
        try? context.save()
        return request
    }

    private var cardID: UUID { MockSeed.workCardID }

    // MARK: When it shows

    @Test func aRequestOnTheTabsShowsTheBanner() throws {
        let h = try harness()
        var visibility: [Bool] = []
        h.model.onVisibilityChange = { visibility.append($0) }
        let request = incoming(in: h.context)

        h.model.receive(request.dto)

        #expect(h.model.current?.id == request.id)
        #expect(h.model.current?.firstName == "Sardor")
        #expect(h.model.current?.detail == "CTO · Payme")
        #expect(h.model.appearanceCount == 1)
        #expect(visibility == [true])
    }

    @Test func connectShowsLiveRequestsItself() throws {
        let h = try harness()
        h.router.present(.connect(cardID: nil))
        h.model.receive(incoming(method: .nearby, in: h.context).dto)
        #expect(h.model.current == nil)

        // Scan / email requests aren't shown by CONNECT, so the banner tells the user.
        let scanned = incoming("Kamila Yusupova", method: .scan, in: h.context)
        h.model.receive(scanned.dto)
        #expect(h.model.current?.id == scanned.id)
    }

    /// The prime case: someone scans your QR (full-screen cover) and taps Connect.
    @Test func showsOverTheQRCode() throws {
        let h = try harness()
        h.router.present(.qr(cardID: cardID))
        let request = incoming(in: h.context)
        h.model.receive(request.dto)
        #expect(h.model.current?.id == request.id)
    }

    @Test func waitsWhileTheUserEditsAndShowsAfterwards() throws {
        let h = try harness()
        h.router.present(.cardEditor(cardID: cardID))
        let request = incoming(in: h.context)
        h.model.receive(request.dto)
        #expect(h.model.current == nil)

        h.router.dismiss()
        h.model.update()
        #expect(h.model.current?.id == request.id)
    }

    @Test func stepsAsideWhenAnEditorOpens() throws {
        let h = try harness()
        let request = incoming(in: h.context)
        h.model.receive(request.dto)
        #expect(h.model.current != nil)

        h.router.present(.addContext(connectionID: UUID()))
        h.model.update()
        #expect(h.model.current == nil)

        h.router.dismiss()
        h.model.update()
        #expect(h.model.current?.id == request.id)
    }

    @Test func blockedExpiredAndAnsweredRequestsAreNotShown() throws {
        let h = try harness()
        let blockedID = UUID()
        let blocked = Connection(fullName: "Blocked Person", source: .nearby)
        blocked.remoteUserID = blockedID
        blocked.isBlocked = true
        h.context.insert(blocked)
        h.model.receive(incoming(peer: blockedID, in: h.context).dto)
        h.model.receive(incoming(method: .nearby, expiresAt: .now.addingTimeInterval(-1), in: h.context).dto)
        let answered = incoming(in: h.context)
        answered.status = .declined
        h.model.receive(answered.dto)
        #expect(h.model.current == nil)
    }

    @Test func aRequestAnsweredInPeopleDisappears() throws {
        let h = try harness()
        let request = incoming(in: h.context)
        h.model.receive(request.dto)
        request.status = .accepted
        h.model.update()
        #expect(h.model.current == nil)
    }

    @Test func notSignedInNothingShows() throws {
        let h = try harness()
        h.router.phase = .onboarding
        h.model.receive(incoming(in: h.context).dto)
        #expect(h.model.current == nil)
    }

    // MARK: Queue

    @Test func laterHidesForGoodAndShowsTheNextOne() throws {
        let h = try harness()
        let first = incoming("Sardor Rashidov", in: h.context)
        let second = incoming("Kamila Yusupova", in: h.context)
        h.model.receive(first.dto)
        h.model.receive(second.dto)
        #expect(h.model.current?.id == first.id)

        h.model.later()
        #expect(h.model.current?.id == second.id)
        #expect(first.status == .pending)   // still waiting in People › Requests

        h.model.later()
        h.model.receive(first.dto)          // a repeated delivery doesn't bring it back
        #expect(h.model.current == nil)
    }

    @Test func onePersonOneBanner() throws {
        let h = try harness()
        let peer = UUID()
        let first = incoming(peer: peer, in: h.context)
        h.model.receive(first.dto)
        h.model.receive(incoming(peer: peer, method: .emailLookup, in: h.context).dto)
        h.model.later()
        #expect(h.model.current == nil)
    }

    // MARK: Actions

    @Test func viewOpensPeopleRequests() throws {
        let h = try harness()
        h.router.select(.home)
        h.router.paths[.people] = [.connectionDetail(id: UUID())]
        h.router.present(.qr(cardID: cardID))
        h.model.receive(incoming(in: h.context).dto)
        h.model.receive(incoming("Kamila Yusupova", in: h.context).dto)

        h.model.view()

        #expect(h.router.selectedTab == .people)
        #expect(h.router.presentations.isEmpty)
        #expect(h.router.paths[.people]?.isEmpty == true)
        #expect(h.model.current == nil)
        h.model.update()
        #expect(h.model.current == nil)     // People lists the rest
    }

    @Test func acceptLandsOnConnected() async throws {
        let h = try harness()
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        h.model.receive(request.dto)
        #expect(h.model.current?.id == request.id)

        await h.model.accept()

        #expect(h.model.current == nil)
        #expect(!h.model.isAccepting)
        guard case .cover(.connected(let connectionID))? = h.router.presentations.last else {
            Issue.record("Expected CONNECTED, got \(h.router.presentations)")
            return
        }
        let connection = try #require(h.context.record(Connection.self, id: connectionID))
        #expect(connection.remoteUserID == request.peerUserID)
        #expect(request.status == .accepted)
    }

    @Test func offlineAcceptStillLandsOnConnected() async throws {
        let h = try harness(online: false)
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        h.model.receive(request.dto)
        await h.model.accept()
        guard case .cover(.connected(let connectionID))? = h.router.presentations.last else {
            Issue.record("Expected CONNECTED, got \(h.router.presentations)")
            return
        }
        #expect(h.context.record(Connection.self, id: connectionID)?.syncState == .pendingUpsert)
        #expect(request.status == .accepted)
    }

    @Test func acceptOverConnectReplacesIt() async throws {
        let h = try harness()
        let request = try #require(try h.context.fetch(ConnectRequest.pendingIncoming).first)
        request.method = .scan
        h.router.present(.connect(cardID: nil))
        h.model.receive(request.dto)
        await h.model.accept()
        #expect(h.router.presentations.count == 1)
        guard case .cover(.connected)? = h.router.presentations.last else {
            Issue.record("Expected CONNECTED, got \(h.router.presentations)")
            return
        }
    }

    @Test func acceptingAnExpiredRequestExplainsInsteadOfConnecting() async throws {
        let h = try harness()
        let request = incoming(method: .nearby, expiresAt: .now.addingTimeInterval(30), in: h.context)
        h.model.receive(request.dto)
        h.model.now = { .now.addingTimeInterval(120) }
        await h.model.accept()
        #expect(h.router.presentations.isEmpty)
        #expect(h.router.toast?.message == "This request has expired")
        #expect(h.model.current == nil)
    }

    // MARK: Live

    @Test func realtimeRequestsReachTheBanner() async throws {
        let h = try harness()
        h.client.startRealtime()
        h.model.start()
        try await Task.sleep(for: .milliseconds(50))
        await h.client.mockServer?.simulateIncomingRequest(method: .scan)
        try await waitUntil("banner shown") { h.model.current?.firstName == "Bekzod" }
    }

    @Test func modalChangesAreObservedWithoutTheView() async throws {
        let h = try harness()
        h.model.start()
        h.router.present(.justMet(cardID: nil))
        let request = incoming(in: h.context)
        h.model.receive(request.dto)
        #expect(h.model.current == nil)
        h.router.dismiss()
        try await waitUntil("shown after JUST_MET closed") { h.model.current?.id == request.id }
    }

    // MARK: Policy

    @Test func bannerTimesOutBeforeTheRequestDoes() {
        let now = Date.now
        #expect(IncomingRequestBannerPolicy.displayDuration(expiresAt: nil, now: now) == .seconds(20))
        #expect(IncomingRequestBannerPolicy.displayDuration(expiresAt: now.addingTimeInterval(8), now: now) == .seconds(8))
        #expect(IncomingRequestBannerPolicy.displayDuration(expiresAt: now.addingTimeInterval(-5), now: now) == .zero)
    }
}
