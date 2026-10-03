import Foundation
import MetlyCore
import Testing
@testable import MetlyNetworking

@Suite("MockMetlyServer", .timeLimit(.minutes(1)))
struct MockMetlyServerTests {
    private func server(_ seed: MockMetlyServer.Seed = .demo) -> MockMetlyServer {
        MockMetlyServer(seed: seed, configuration: .instant)
    }

    @Test("Publishing assigns a {firstname}-{4} slug and a metly.link URL")
    func slugAssignment() async throws {
        let server = server(.newAccount)
        let now = Date.now
        let profile = ProfileDTO(id: UUID(), fullName: "Ömer Karimov", jobTitle: "", company: "", contactFields: ContactField.defaults,
                                 defaultCardID: nil, linksPaused: false, notificationPrefs: NotificationPrefs(),
                                 privacySettings: PrivacySettings(), isSetupComplete: true, createdAt: now, updatedAt: now)
        _ = try await server.updateProfile(profile)
        let card = try await server.publishCard(CardDTO(id: UUID(), name: "Work", sortOrder: 0, design: CardDesign(),
                                                        createdAt: now, updatedAt: now))
        let slug = try #require(card.slug)
        #expect(slug.wholeMatch(of: /omer-[a-z0-9]{4}/) != nil)
        #expect(card.url == Brand.cardURL(slug: slug))
        #expect(card.publishState == .published)

        // Republishing keeps the slug.
        var edited = card
        edited.name = "Work 2"
        edited.updatedAt = now.addingTimeInterval(1)
        #expect(try await server.publishCard(edited).slug == slug)
    }

    @Test("Free plan: a third card is rejected server-side")
    func freeCardLimit() async throws {
        let server = server()
        let card = CardDTO(id: UUID(), name: "Third", sortOrder: 2, design: CardDesign(), createdAt: .now, updatedAt: .now)
        do {
            _ = try await server.upsertCard(card)
            Issue.record("Expected plan_limit_reached")
        } catch let error as APIError {
            #expect(error.code == .planLimitReached)
            #expect(error.statusCode == 403)
        }
        _ = try await server.verify(VerifyTransactionRequest(signedTransaction: "header.payload.signature"))
        #expect(try await server.upsertCard(card).slug != nil)
    }

    @Test("Public profiles: available, paused, own card, unknown")
    func publicProfiles() async throws {
        let server = server()
        let kamila = try await server.publicProfile(slug: "kamila-x1y2")
        #expect(kamila.status == .available)
        #expect(kamila.owner?.fullName == "Kamila Yusupova")
        // Connected (demo connection D1 is Kamila) → connections-only phone is visible too.
        #expect(kamila.viewer?.isConnected == true)
        #expect(kamila.fields.contains { $0.kind == .phone })
        #expect(kamila.snapshot?.url == Brand.cardURL(slug: "kamila-x1y2"))

        let nodira = try await server.publicProfile(slug: "nodira-n5m1")
        #expect(nodira.viewer?.isConnected == false)
        #expect(nodira.fields.allSatisfy { $0.privacy == .public })

        let paused = try await server.publicProfile(slug: "lola-p0z3")
        #expect(paused.status == .paused)
        #expect(paused.owner == nil)

        let own = try await server.publicProfile(slug: "aziza-w7k2")
        #expect(own.viewer?.isSelf == true)
        #expect(own.fields.allSatisfy { $0.privacy != .private })

        await #expect(throws: APIError.notFound("Card")) { _ = try await server.publicProfile(slug: "nobody-0000") }
    }

    @Test("A connect request is accepted by the mock peer and delivered on the realtime stream")
    func connectAccepted() async throws {
        let server = server(.newAccount)
        let stream = await server.connectEvents()
        let request = try await server.sendRequest(SendConnectRequest(toToken: "mock-peer-sardor", cardID: UUID(), method: .nearby))
        #expect(request.status == .pending)
        #expect(request.direction == .outgoing)

        var outcome: (ConnectRequestDTO, ConnectionDTO?)?
        for await event in stream {
            if case .requestUpdated(let updated, let connection) = event, updated.id == request.id {
                outcome = (updated, connection)
                break
            }
        }
        #expect(outcome?.0.status == .accepted)
        #expect(outcome?.1?.remoteUserID == MockSeed.peer(token: "mock-peer-sardor")?.userID)
        #expect(outcome?.1?.theirCard != nil)
        #expect(await server.liveRecords().connections.count == 1)
    }

    @Test("Nodira never answers → the request expires")
    func connectExpires() async throws {
        let server = server(.newAccount)
        let stream = await server.connectEvents()
        let request = try await server.sendRequest(SendConnectRequest(toSlug: "nodira-n5m1", cardID: UUID(), method: .scan))
        var status: ConnectRequestStatus?
        for await event in stream {
            if case .requestUpdated(let updated, _) = event, updated.id == request.id {
                status = updated.status
                break
            }
        }
        #expect(status == .expired)
    }

    @Test func incomingRequestAcceptCreatesConnection() async throws {
        let server = server()
        let response = try await server.acceptRequest(id: MockSeed.incomingRequestID, AcceptConnectRequest(cardID: MockSeed.workCardID))
        #expect(response.request.status == .accepted)
        #expect(response.connection.fullName == "Bekzod Tursunov")
        #expect(response.connection.mySharedCardID == MockSeed.workCardID)
        await #expect(throws: APIError.self) {
            _ = try await server.declineRequest(id: MockSeed.incomingRequestID)   // no longer pending
        }
    }

    @Test func walletPassNeedsTheServer() async {
        let server = server()
        await #expect(throws: APIError.serverRequired("Wallet passes need the server.")) {
            _ = try await server.walletPass(cardID: MockSeed.workCardID)
        }
    }

    @Test("Pull pages through every record, then deltas include tombstones")
    func pullPaging() async throws {
        let server = server()
        var cursor: String?
        var ids = Set<UUID>()
        var pages = 0
        repeat {
            let page = try await server.pull(since: cursor, limit: 4)
            page.changes.cards.forEach { ids.insert($0.id) }
            page.changes.connections.forEach { ids.insert($0.id) }
            page.changes.followUps.forEach { ids.insert($0.id) }
            page.changes.events.forEach { ids.insert($0.id) }
            page.changes.connectRequests.forEach { ids.insert($0.id) }
            if let profile = page.changes.profile { ids.insert(profile.id) }
            cursor = page.cursor
            pages += 1
            if !page.hasMore { break }
        } while pages < 20
        #expect(ids.count == 15)   // profile + 2 cards + event + 6 connections + 4 follow-ups + 1 request
        #expect(pages == 4)

        let empty = try await server.pull(since: cursor, limit: 100)
        #expect(empty.changes.isEmpty)

        _ = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(tombstones: [
            TombstoneDTO(type: .connection, id: MockSeed.connectionIDs[0], deletedAt: .now),
        ])))
        let delta = try await server.pull(since: empty.cursor, limit: 100)
        // The connection and its follow-up (cascade) are tombstoned.
        #expect(Set(delta.changes.tombstones.map(\.id)) == [MockSeed.connectionIDs[0], MockSeed.followUpIDs[0]])

        await #expect(throws: APIError.self) { _ = try await server.pull(since: "garbage", limit: 10) }
    }

    @Test("Push applies LWW: older writes come back stale with the newer canonical record")
    func pushLastWriteWins() async throws {
        let server = server()
        var connection = try #require(await server.liveRecords().connections.first { $0.id == MockSeed.connectionIDs[1] })
        let serverVersion = connection.updatedAt

        connection.note = "Old edit"
        connection.updatedAt = serverVersion.addingTimeInterval(-60)
        let stale = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(connections: [connection])))
        #expect(stale.results.first?.status == .stale)
        #expect(stale.records.connections.first?.note == "")

        connection.note = "New edit"
        connection.updatedAt = serverVersion.addingTimeInterval(60)
        let applied = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(connections: [connection])))
        #expect(applied.results.first?.status == .applied)
        #expect(applied.records.connections.first?.note == "New edit")
    }

    @Test("A second connection for the same Metly user merges into the first")
    func connectionUniquePerRemoteUser() async throws {
        let server = server()
        let kamilaID = MockSeed.peers[0].userID
        let duplicate = ConnectionDTO(id: UUID(), remoteUserID: kamilaID, fullName: "Kamila Yusupova", source: .connectRequest,
                                      context: MeetingContext(), note: "Met again", createdAt: .now, updatedAt: .now)
        let response = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(connections: [duplicate])))
        #expect(response.results.first?.status == .applied)
        #expect(response.records.connections.first?.id == MockSeed.connectionIDs[0])
        #expect(response.records.connections.first?.note == "Met again")
        #expect(response.records.tombstones.map(\.id) == [duplicate.id])
        #expect(await server.liveRecords().connections.filter { $0.remoteUserID == kamilaID }.count == 1)
    }

    @Test("Share-back merge pair: soft-deleted share-back + updated just-met record are both accepted")
    func shareBackMergePair() async throws {
        let server = server()
        let notice = await server.simulateShareBack(name: "Dilshod Aliev", phone: "+998 90 000 00 00")
        #expect(notice.mergeResult == .created)
        var justMet = try #require(await server.liveRecords().connections.first { $0.id == MockSeed.connectionIDs[5] })
        justMet.phone = notice.connection.phone
        justMet.isMerged = true
        justMet.updatedAt = .now.addingTimeInterval(1)
        let response = try await server.push(SyncPushRequest(deviceID: nil, changes: SyncChanges(
            connections: [justMet],
            tombstones: [TombstoneDTO(type: .connection, id: notice.connection.id, deletedAt: .now.addingTimeInterval(1))])))
        #expect(response.results.map(\.status) == [.applied, .applied])
        let live = await server.liveRecords().connections
        #expect(!live.contains { $0.id == notice.connection.id })
        #expect(live.first { $0.id == justMet.id }?.isMerged == true)
    }

    @Test("Share-back dedupes by phone digits and merges into a just-met placeholder by first name")
    func shareBackRules() async throws {
        let server = server()
        let byTelegram = await server.simulateShareBack(name: "Jasur A.", telegram: "@JASUR")
        #expect(byTelegram.mergeResult == .dedupedByPhoneOrTelegram)
        #expect(byTelegram.connection.id == MockSeed.connectionIDs[3])

        var placeholder = ConnectionDTO(id: UUID(), fullName: "Malika", source: .justMet, context: MeetingContext(),
                                        isPendingMerge: true, createdAt: .now, updatedAt: .now)
        placeholder.jobTitle = "Met via your QR"
        _ = await server.simulateRemoteChanges(SyncChanges(connections: [placeholder]))
        let merged = await server.simulateShareBack(name: "malika Rahimova", phone: "+998 91 111 22 33")
        #expect(merged.mergeResult == .mergedWithJustMet)
        #expect(merged.connection.id == placeholder.id)
        #expect(merged.connection.isMerged)
    }

    @Test func deferredInviteOnlyWhenEnabled() async throws {
        let request = DeferredLinkClaimRequest(installID: "i", fingerprint: DeviceFingerprint(model: "iPhone", osVersion: "18.0",
                                                                                                locale: "en_US", timeZone: "UTC",
                                                                                                preferredLanguages: ["en"]))
        #expect(try await server().claim(request) == nil)
        var configuration = MockMetlyServer.Configuration.instant
        configuration.deferredInviteEnabled = true
        let invite = try await MockMetlyServer(configuration: configuration).claim(request)
        #expect(invite?.invite.ownerName == "Kamila Yusupova")
        #expect(invite?.invite.cardSlug == "kamila-x1y2")
    }

    @Test func unreachableServerIsOffline() async {
        let server = MockMetlyServer(seed: .demo, configuration: .instant, isReachable: false)
        await #expect(throws: APIError.offline) { _ = try await server.listCards() }
    }

    @Test func demoSeedMatchesPreviewIDs() {
        let account = MockSeed.demoAccount()
        #expect(account.profile?.fullName == "Aziza Karimova")
        #expect(account.cards.map(\.id) == [MockSeed.workCardID, MockSeed.personalCardID])
        #expect(account.connections.map(\.id) == MockSeed.connectionIDs)
        #expect(account.followUps.compactMap(\.connectionID).allSatisfy(MockSeed.connectionIDs.contains))
        #expect(account.connections.first?.eventID == MockSeed.eventID)
        #expect(account.minimal.cards.count == 1)
    }
}

@Suite("KeychainSessionStore", .enabled(if: KeychainProbe.isAvailable, "Keychain needs an entitled host"))
struct KeychainSessionStoreTests {
    @Test func saveLoadClear() throws {
        let service = "com.metly.tests.\(UUID().uuidString)"
        let store = KeychainSessionStore(service: service)
        #expect(store.load() == nil)
        let session = AuthSession.test(access: "a1", refresh: "r1")
        try store.save(session)
        #expect(store.load() == session)
        // A fresh instance (no cache) reads the same item.
        #expect(KeychainSessionStore(service: service).load()?.accessToken == "a1")

        var rotated = session
        rotated.accessToken = "a2"
        try store.save(rotated)
        #expect(KeychainSessionStore(service: service).load()?.accessToken == "a2")

        store.clear()
        #expect(store.load() == nil)
        #expect(KeychainSessionStore(service: service).load() == nil)
    }
}

enum KeychainProbe {
    static let isAvailable: Bool = {
        let store = KeychainSessionStore(service: "com.metly.tests.probe")
        do {
            try store.save(.test())
            store.clear()
            return true
        } catch {
            return false
        }
    }()
}
