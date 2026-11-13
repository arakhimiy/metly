import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import Testing
@testable import MetlyData

/// Regression tests for sync-engine bugs found in the bug hunt (one per bug).
@MainActor
@Suite("Sync regressions", .timeLimit(.minutes(1)))
struct SyncRegressionTests {

    // MARK: Undo window

    @Test("Undo after the debounced pass still restores the record (tombstones wait out the Undo window)")
    func undoSurvivesSyncPass() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        harness.engine.tombstoneGracePeriod = 60
        await harness.engine.syncNow()
        let id = MockSeed.connectionIDs[4]
        let madina = try #require(harness.connection(id))

        madina.markDeleted()                 // People › Remove → toast with Undo (4 s)
        try harness.context.save()
        await harness.engine.syncNow()       // the debounced pass fires ~1.5 s later
        #expect(!harness.engine.hasPushableChanges())   // nothing due yet → no save/sync ping-pong
        try #require(harness.connection(id) != nil, "the tombstone was hard-deleted while Undo was still on screen")

        madina.restore()                     // Undo
        try harness.context.save()
        await harness.engine.syncNow()

        #expect(harness.connection(id)?.deletedAt == nil)
        #expect(harness.connection(id)?.syncState == .synced)
        #expect(await harness.server.liveRecords().connections.contains { $0.id == id })
        #expect(await !harness.server.tombstoneIDs.contains(id))
    }

    @Test("A deferred tombstone is pushed by itself once the Undo window has passed")
    func deferredTombstoneGoesOutLater() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        harness.engine.tombstoneGracePeriod = 2   // generous: the test must not depend on a fast machine
        await harness.engine.syncNow()
        let id = MockSeed.connectionIDs[4]
        try #require(harness.connection(id)).markDeleted()
        try harness.context.save()

        await harness.engine.syncNow()
        #expect(harness.connection(id) != nil)
        #expect(await !harness.server.tombstoneIDs.contains(id))

        // No further save or syncNow: the engine schedules the pass for when the tombstone is due.
        #expect(await eventually(timeout: .seconds(8)) { harness.connection(id) == nil })
        #expect(await harness.server.tombstoneIDs.contains(id))
    }

    @Test("A tombstone that falls due during a slow pass still goes out right after it")
    func tombstoneDueMidPassIsScheduled() async throws {
        let hooks = HookedAPI.Hooks()
        let harness = try SyncHarness(local: .full, server: .demo, hooks: hooks)
        harness.engine.tombstoneGracePeriod = 1.5
        await harness.engine.syncNow()
        let id = MockSeed.connectionIDs[4]
        try #require(harness.connection(id)).markDeleted()
        try harness.context.save()

        hooks.setBeforePull { _ in try await Task.sleep(for: .seconds(2.5)) }   // the pass outlives the window
        await harness.engine.syncNow()
        hooks.setBeforePull(nil)
        #expect(harness.connection(id) != nil)   // held when the pass collected its push

        #expect(await eventually(timeout: .seconds(8)) { harness.connection(id) == nil })
    }

    // MARK: reset() vs an in-flight pass

    @Test("reset() mid-pass: a late response never refills the wiped store, and the next pass isn't disturbed")
    func resetStopsInFlightPass() async throws {
        let firstEntered = Gate(), firstRelease = Gate(), secondEntered = Gate(), secondRelease = Gate()
        let hooks = HookedAPI.Hooks { call in
            switch call {
            case 1:
                firstEntered.open()
                await firstRelease.wait()
            case 2:
                secondEntered.open()
                await secondRelease.wait()
            default:
                break
            }
        }
        let harness = try SyncHarness(local: .signedOut, server: .demo, hooks: hooks)
        let first = Task { await harness.engine.syncNow() }
        await firstEntered.wait()

        // Sign-out while the first pull's response is already on its way back.
        harness.engine.reset()
        try MetlyModelContainer.wipe(harness.context)

        // Signed in again: a new pass starts and waits for its own pull.
        let second = Task { await harness.engine.syncNow() }
        await secondEntered.wait()

        firstRelease.open()
        await first.value
        #expect(harness.count(Connection.self) == 0)
        #expect(harness.count(Profile.self) == 0)
        #expect(harness.state.cursor == nil)
        #expect(harness.engine.status == .syncing)   // the stale pass must not touch the live pass's status

        // Another request joins the running pass instead of starting a parallel one.
        let third = Task { await harness.engine.syncNow() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(hooks.pullCount == 2)

        secondRelease.open()
        await second.value
        await third.value
        #expect(harness.count(Connection.self) == 6)
        #expect(harness.engine.status == .idle)
    }

    @Test("BGTask expiry cancels the running pass so the task completes right away")
    func backgroundExpiryCancelsPass() async throws {
        let entered = Gate()
        let hooks = HookedAPI.Hooks { _ in
            entered.open()
            try await Task.sleep(for: .seconds(30))   // slow network call (cancellable, like URLSession)
        }
        let harness = try SyncHarness(local: .full, server: .demo, hooks: hooks)
        let work = harness.engine.backgroundPass()
        await entered.wait()

        work.cancel()   // what `expirationHandler` does
        let finished = Gate()
        Task {
            _ = await work.value
            finished.open()
        }
        #expect(await eventually { finished.isOpen })
        harness.engine.reset()   // unblock the pass if the expiry didn't
        #expect(await work.value == false)
    }

    // MARK: Pull

    @Test("Paged pulls keep follow-up → person and person → event links when the parent comes on a later page")
    func pagedPullKeepsRelationships() async throws {
        let harness = try SyncHarness(local: .signedOut, server: .demo)
        // Change the parents after their children so they sort later in the change feed.
        _ = try await harness.server.endEvent(id: MockSeed.eventID)
        var kamila = try #require(await harness.server.liveRecords().connections.first { $0.id == MockSeed.connectionIDs[0] })
        kamila.note = "Edited on the iPad"
        kamila.updatedAt = .now
        await harness.server.simulateRemoteChanges(SyncChanges(connections: [kamila]))
        harness.engine.pullPageSize = 2

        await harness.engine.syncNow()

        #expect(harness.count(FollowUp.self) == 4)
        #expect(harness.context.record(FollowUp.self, id: MockSeed.followUpIDs[0])?.connection?.id == MockSeed.connectionIDs[0])
        #expect(harness.connection(MockSeed.connectionIDs[1])?.event?.id == MockSeed.eventID)
        #expect(harness.connection(MockSeed.connectionIDs[2])?.event?.id == MockSeed.eventID)
        #expect(!harness.engine.hasPushableChanges())
    }

    @Test("An interrupted full snapshot restarts from scratch, so records the server lost are still pruned")
    func interruptedSnapshotRestarts() async throws {
        let hooks = HookedAPI.Hooks { call in
            if call == 3 { throw APIError.offline }   // 1: 410 cursor_expired, 2: snapshot page 1, 3: page 2 fails
        }
        let harness = try SyncHarness(local: .full, server: .demo, hooks: hooks)
        let ghost = Connection(fullName: "Ghost", source: .manual)
        ghost.syncState = .synced
        harness.context.insert(ghost)
        try harness.context.save()
        harness.state.cursor = "mock:999999"
        harness.engine.pullPageSize = 3

        await harness.engine.syncNow()
        #expect(harness.engine.status == .offline)
        #expect(harness.state.cursor == nil)   // half a snapshot must not pass for a delta cursor

        await harness.engine.syncNow()
        #expect(harness.engine.status == .idle)
        #expect(harness.connection(ghost.id) == nil)
        #expect(harness.count(Connection.self) == 6)
    }

    // MARK: Connect / merges

    @Test("A pushed duplicate that the server merged into its twin is settled from the echo, keeping the twin's fields")
    func twinMergeEchoSettles() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let peer = UUID()
        let twin = ConnectionDTO(id: UUID(), remoteUserID: peer, fullName: "Bobur", source: .nearby, context: MeetingContext(),
                                 note: "Met at the Uzum booth", createdAt: .now.addingTimeInterval(-600),
                                 updatedAt: .now.addingTimeInterval(-600))
        await harness.server.simulateRemoteChanges(SyncChanges(connections: [twin]))
        // Before pulling it, the app creates its own record for the same Nameshake user (offline accept).
        let local = Connection(fullName: "Bobur Aliev", source: .nearby)
        local.remoteUserID = peer
        harness.context.insert(local)
        try harness.context.save()

        await harness.engine.syncNow()

        #expect(local.id == twin.id)
        #expect(local.syncState == .synced)
        #expect(local.note == "Met at the Uzum booth")
        #expect(harness.all(Connection.self).filter { $0.remoteUserID == peer }.count == 1)
        #expect(!harness.engine.hasPushableChanges())

        await harness.engine.syncNow()   // must not push the pre-merge copy over the server's merge
        let server = await harness.server.liveRecords().connections.first { $0.id == twin.id }
        #expect(server?.note == "Met at the Uzum booth")
        #expect(server?.fullName == "Bobur Aliev")
    }

    @Test("A follow-up pushed with a duplicate connection moves to the server's twin with it")
    func twinMergeKeepsFollowUps() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        await harness.engine.syncNow()
        let peer = UUID()
        let twin = ConnectionDTO(id: UUID(), remoteUserID: peer, fullName: "Bobur", source: .nearby, context: MeetingContext(),
                                 createdAt: .now.addingTimeInterval(-600), updatedAt: .now.addingTimeInterval(-600))
        await harness.server.simulateRemoteChanges(SyncChanges(connections: [twin]))
        // Offline accept → CONNECTED: the person and their reminder are created locally together.
        let local = Connection(fullName: "Bobur Aliev", source: .nearby)
        local.remoteUserID = peer
        harness.context.insert(local)
        let reminder = FollowUp(title: "Send the deck", channel: .telegram, dueAt: .now.addingTimeInterval(86_400), connection: local)
        harness.context.insert(reminder)
        try harness.context.save()

        await harness.engine.syncNow()

        #expect(reminder.connection?.id == twin.id)
        #expect(reminder.syncState == .synced)
        let server = await harness.server.liveRecords().followUps.first { $0.id == reminder.id }
        #expect(server?.connectionID == twin.id)   // not the tombstoned duplicate's id
    }

    // MARK: Avatars

    @Test("Peer avatars (avatarUrl) are downloaded into avatarData once, and cleared when removed")
    func connectionAvatars() async throws {
        let harness = try SyncHarness(local: .signedOut, server: .demo)
        let kamila = MockSeed.connectionIDs[0]
        await harness.server.simulateAvatar(connectionID: kamila, data: TestImage.png)

        await harness.engine.syncNow()
        #expect(harness.connection(kamila)?.avatarData == TestImage.png)
        #expect(harness.connection(kamila)?.syncState == .synced)
        #expect(!harness.engine.hasPushableChanges())

        // A photo the app put there itself (share-back merge) is left alone.
        let jasur = try #require(harness.connection(MockSeed.connectionIDs[3]))
        jasur.avatarData = TestImage.jpeg
        try harness.context.save()

        let calls = await harness.server.callCount
        await harness.engine.syncNow()
        #expect(await harness.server.callCount - calls == 1)   // cached: just the pull, no re-download

        await harness.server.simulateAvatar(connectionID: kamila, data: nil)
        await harness.engine.syncNow()
        #expect(harness.connection(kamila)?.avatarData == nil)
        #expect(jasur.avatarData == TestImage.jpeg)
    }
}

@MainActor
@Suite("Auth regressions")
struct AuthRegressionTests {
    private let credential = AppleSignInCredential(userID: "001234.abcd", identityToken: Data("header.payload.sig".utf8),
                                                   authorizationCode: Data("code".utf8),
                                                   fullName: PersonNameComponents(givenName: "Aziza", familyName: "Karimova"),
                                                   email: "aziza@privaterelay.appleid.com")

    @Test("Sign-out removes the push registration while the session is still valid, then logs out")
    func signOutUnregistersPushBeforeLogout() async throws {
        let hooks = HookedAPI.Hooks(revokesOnLogout: true)   // like the real server: logout kills the session
        let harness = try SyncHarness(local: .signedOut, server: .demo, hooks: hooks)
        let api = HookedAPI(server: harness.server, hooks: hooks)
        let defaults = UserDefaults(suiteName: "metly.tests.\(UUID().uuidString)")!
        let auth = AuthService(api: api, sessionStore: InMemorySessionStore(), container: harness.container,
                               preferences: AppPreferences(store: defaults), sync: harness.engine, isMock: false,
                               observeRevocation: false)
        let push = PushRegistrar(api: api, state: harness.state, defaults: defaults)
        push.isSignedIn = { [auth] in auth.isSignedIn }
        auth.onSignedOut = { [push] in await push.unregister() }   // what MetlyServiceFactory wires
        harness.engine.shouldSync = { [auth] in auth.isSignedIn }

        _ = try await auth.signIn(apple: credential)
        await push.register(deviceToken: Data([0xAB, 0xCD, 0xEF]))
        #expect(hooks.log == ["registerDevice"])

        await auth.signOut()

        // Otherwise this device keeps getting the old account's pushes (names, follow-ups) after sign-out.
        #expect(hooks.log == ["registerDevice", "unregisterDevice", "logout"])
        #expect(!auth.isSignedIn)
        #expect(harness.count(Connection.self) == 0)
    }

    private func makeAuth(hooks: HookedAPI.Hooks) throws -> (harness: SyncHarness, auth: AuthService, store: InMemorySessionStore) {
        let harness = try SyncHarness(local: .signedOut, server: .demo, hooks: hooks)
        let store = InMemorySessionStore()
        let auth = AuthService(api: HookedAPI(server: harness.server, hooks: hooks), sessionStore: store,
                               container: harness.container,
                               preferences: AppPreferences(store: UserDefaults(suiteName: "metly.tests.\(UUID().uuidString)")!),
                               sync: harness.engine, isMock: false, observeRevocation: false)
        harness.engine.shouldSync = { [auth] in auth.isSignedIn }
        return (harness, auth, store)
    }

    @Test("Signing in again while the previous sign-out is still logging out keeps the new session and data")
    func signInDuringSlowSignOut() async throws {
        let hooks = HookedAPI.Hooks()
        let (harness, auth, store) = try makeAuth(hooks: hooks)
        _ = try await auth.signIn(apple: credential)
        let logoutEntered = Gate(), logoutRelease = Gate()
        hooks.setBeforeLogout {
            logoutEntered.open()
            await logoutRelease.wait()
        }

        // SignOutSection shows onboarding right away, then awaits signOut(); the user signs in again.
        let signOut = Task { await auth.signOut() }
        await logoutEntered.wait()
        hooks.setBeforeLogout(nil)
        let signIn = Task { try await auth.signIn(apple: credential) }
        try await Task.sleep(for: .milliseconds(100))

        logoutRelease.open()
        await signOut.value
        let result = try await signIn.value

        #expect(!result.needsSetup)
        #expect(auth.isSignedIn)
        #expect(store.load() != nil)
        #expect(harness.count(Connection.self) == 6)
    }

    @Test("Sign-out's network clean-up is bounded: a hanging server never delays the wipe")
    func signOutIsBounded() async throws {
        let hooks = HookedAPI.Hooks()
        let (harness, auth, store) = try makeAuth(hooks: hooks)
        _ = try await auth.signIn(apple: credential)
        auth.signOutNetworkTimeout = .milliseconds(200)
        hooks.setBeforeLogout { try await Task.sleep(for: .seconds(30)) }

        let started = ContinuousClock.now
        await auth.signOut()

        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(!auth.isSignedIn)
        #expect(store.load() == nil)
        #expect(harness.count(Connection.self) == 0)
    }
}

@MainActor
@Suite("Subscription regressions")
struct SubscriptionRegressionTests {
    /// A StoreKit-shaped JWS (the mock reads `productId` / `expiresDate` from the payload).
    static func jws(productID: String, expires: Date) throws -> String {
        let payload = try JSONSerialization.data(withJSONObject: ["productId": productID,
                                                                  "expiresDate": expires.timeIntervalSince1970 * 1000])
        let base64URL = payload.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJFUzI1NiJ9.\(base64URL).c2ln"
    }

    @Test("A server reply for a stale transaction never downgrades the Pro plan StoreKit proves")
    func serverReplyNeverDowngradesStoreKitPro() async throws {
        let server = MockMetlyServer(seed: .demo, configuration: .instant)
        let entitlements = Entitlements(plan: .pro)   // what SubscriptionManager derived from StoreKit
        entitlements.productID = "app.nameshake.ios.pro.yearly"
        let renews = Date.now.addingTimeInterval(300 * 86_400)
        entitlements.renewsAt = renews
        entitlements.willRenew = true
        let verifier = SubscriptionVerifier(api: server, entitlements: entitlements)

        // Transaction.updates delivers the expired/refunded monthly plan the user had upgraded from.
        _ = try await verifier.verify(signedTransaction: Self.jws(productID: "app.nameshake.ios.pro.monthly",
                                                                   expires: .now.addingTimeInterval(-86_400)))

        #expect(entitlements.plan == .pro)
        #expect(entitlements.productID == "app.nameshake.ios.pro.yearly")
        #expect(entitlements.renewsAt == renews)
        #expect(entitlements.willRenew)
    }

    @Test("Pro known only to the server (bought under another Apple ID) is still adopted")
    func serverProIsAdopted() async throws {
        let server = MockMetlyServer(seed: .demo, configuration: .instant)
        let entitlements = Entitlements(plan: .free)
        let verifier = SubscriptionVerifier(api: server, entitlements: entitlements)
        _ = try await verifier.verify(signedTransaction: Self.jws(productID: "app.nameshake.ios.pro.yearly",
                                                                   expires: .now.addingTimeInterval(365 * 86_400)))
        #expect(entitlements.plan == .pro)
        #expect(entitlements.productID == "app.nameshake.ios.pro.yearly")
    }
}

@MainActor
@Suite("MetlyClient regressions")
struct ClientRegressionTests {
    @Test("Connecting with a card that isn't on the server yet publishes it first")
    func connectPublishesUnsyncedCard() async throws {
        let harness = try SyncHarness(local: .signedOut, server: .newAccount)
        harness.context.insert(Profile(fullName: "Dilnoza Ergasheva", isSetupComplete: true))
        let card = Card(name: "Work")   // created seconds ago: the debounced sync hasn't pushed it yet
        harness.context.insert(card)
        try harness.context.save()
        let client = MetlyClient(api: harness.server, container: harness.container, mockServer: harness.server)

        let request = try await client.sendConnectRequest(to: .slug("nodira-n5m1"), cardID: card.id, method: .scan)

        #expect(request.myCardID == card.id)
        #expect(await harness.server.liveRecords().cards.contains { $0.id == card.id })
        #expect(card.syncState == .synced)
        #expect(!card.slug.isEmpty)
    }

    @Test("Accepted without a connection in the event: never routes to a removed record, finds the live one")
    func acceptedOutcomeSkipsRemovedRecords() async throws {
        let harness = try SyncHarness(local: .signedOut, server: .newAccount)
        let sardor = try #require(MockSeed.peer(token: "mock-peer-sardor"))
        let removed = Connection(fullName: "Sardor (removed)", source: .scanQR)
        removed.remoteUserID = sardor.userID
        harness.context.insert(removed)
        removed.markDeleted()                     // People › Remove, tombstone not pushed yet
        try harness.context.save()
        // Realtime is down: the outcome comes from GET /v1/connect/requests/{id} after the deadline.
        let client = MetlyClient(api: harness.server, container: harness.container, mockServer: harness.server)

        let request = try await client.sendConnectRequest(to: .nearbyToken("mock-peer-sardor"), cardID: MockSeed.workCardID,
                                                          method: .nearby)
        let outcome = await client.outcome(of: request)

        guard case .accepted(let connectionID) = outcome else {
            Issue.record("Expected .accepted, got \(outcome)")
            return
        }
        #expect(connectionID != removed.id)
        #expect(harness.connection(connectionID)?.deletedAt == nil)
        #expect(harness.connection(connectionID)?.remoteUserID == sardor.userID)
    }

    @Test("Accepting with an edited card sends the edit before the accept")
    func acceptPublishesEditedCard() async throws {
        let harness = try SyncHarness(local: .full, server: .demo)
        let client = MetlyClient(api: harness.server, container: harness.container, mockServer: harness.server)
        let card = try #require(harness.context.record(Card.self, id: MockSeed.personalCardID))
        card.name = "Weekend"
        card.markChanged()
        try harness.context.save()
        let request = try #require(harness.context.record(ConnectRequest.self, id: MockSeed.incomingRequestID))

        _ = try await client.accept(request, sharing: card.id)

        #expect(await harness.server.liveRecords().cards.first { $0.id == card.id }?.name == "Weekend")
        #expect(card.syncState == .synced)
    }
}
