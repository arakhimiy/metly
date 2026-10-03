import Foundation
import MetlyCore
import MetlyNetworking
import SwiftData
import Testing
@testable import MetlyData

@MainActor
@Suite("AuthService")
struct AuthServiceTests {
    private struct Fixture {
        let harness: SyncHarness
        let store: InMemorySessionStore
        let preferences: AppPreferences
        let auth: AuthService

        @MainActor
        init(local: PreviewSeed.Variant = .signedOut, server: MockMetlyServer.Seed, isMock: Bool = false) throws {
            harness = try SyncHarness(local: local, server: server)
            store = InMemorySessionStore()
            preferences = AppPreferences(store: UserDefaults(suiteName: "metly.tests.\(UUID().uuidString)")!)
            auth = AuthService(api: harness.server, sessionStore: store, container: harness.container, preferences: preferences,
                               sync: harness.engine, isMock: isMock, observeRevocation: false)
            harness.engine.shouldSync = { [auth] in auth.isSignedIn }
        }
    }

    private let appleCredential = AppleSignInCredential(userID: "001234.abcd", identityToken: Data("header.payload.sig".utf8),
                                                        authorizationCode: Data("code".utf8),
                                                        fullName: PersonNameComponents(givenName: "Aziza", familyName: "Karimova"),
                                                        email: "aziza@privaterelay.appleid.com")

    @Test("New account → session in the store, needs setup, name prefilled")
    func newAccountSignIn() async throws {
        let fixture = try Fixture(server: .newAccount)
        #expect(!fixture.auth.isSignedIn)
        let result = try await fixture.auth.signIn(apple: appleCredential)
        #expect(result.needsSetup)
        #expect(result.suggestedName == "Aziza Karimova")
        #expect(fixture.auth.isSignedIn)
        #expect(fixture.store.load()?.appleUserID == "001234.abcd")
        #expect(fixture.store.load()?.email == "aziza@privaterelay.appleid.com")
    }

    @Test("Returning user → data synced down before setup is decided")
    func returningUserSignIn() async throws {
        let fixture = try Fixture(server: .demo)
        let result = try await fixture.auth.signIn(google: GoogleSignInCredential(idToken: "id-token", accessToken: nil,
                                                                                  fullName: nil, email: "aziza@tezkor.uz"))
        #expect(!result.needsSetup)
        #expect(fixture.harness.count(Connection.self) == 6)
        #expect(fixture.harness.context.currentProfile()?.isSetupComplete == true)
    }

    @Test("Signed in without a profile stays signed in (setup not finished survives relaunch)")
    func sessionWithoutProfile() async throws {
        let fixture = try Fixture(server: .newAccount)
        _ = try await fixture.auth.signIn(apple: appleCredential)
        let relaunched = AuthService(api: fixture.harness.server, sessionStore: fixture.store, container: fixture.harness.container,
                                     preferences: fixture.preferences, sync: fixture.harness.engine, isMock: false,
                                     observeRevocation: false)
        #expect(fixture.harness.context.currentProfile() == nil)
        #expect(relaunched.isSignedIn)
    }

    @Test("Sign out wipes store, session, sync bookkeeping and preferences")
    func signOutWipes() async throws {
        let fixture = try Fixture(server: .demo)
        _ = try await fixture.auth.signIn(apple: appleCredential)
        fixture.preferences.hasCompletedOnboarding = true
        #expect(fixture.harness.state.cursor != nil)

        await fixture.auth.signOut()
        await fixture.auth.signOut()   // idempotent

        #expect(!fixture.auth.isSignedIn)
        #expect(fixture.store.load() == nil)
        #expect(fixture.harness.count(Connection.self) == 0)
        #expect(fixture.harness.context.currentProfile() == nil)
        #expect(fixture.harness.state.cursor == nil)
        #expect(!fixture.preferences.hasCompletedOnboarding)
    }

    @Test("Delete account removes the server account, then wipes locally")
    func deleteAccount() async throws {
        let fixture = try Fixture(server: .demo)
        _ = try await fixture.auth.signIn(apple: appleCredential)
        try await fixture.auth.deleteAccount()
        #expect(!fixture.auth.isSignedIn)
        #expect(fixture.harness.count(Card.self) == 0)
        await #expect(throws: APIError.unauthorized) { _ = try await fixture.harness.server.fetchMe() }
    }

    @Test("Signing in as a different account wipes the previous account's data first")
    func differentAccountWipes() async throws {
        let fixture = try Fixture(local: .full, server: .newAccount)
        fixture.harness.state.lastUserID = UUID()   // data on the device belongs to someone else
        _ = try await fixture.auth.signIn(apple: appleCredential)
        #expect(fixture.harness.count(Connection.self) == 0)
    }

    @Test("Expired session flips isSignedIn without wiping (the shell routes, then signs out)")
    func sessionExpiry() async throws {
        let fixture = try Fixture(server: .demo)
        _ = try await fixture.auth.signIn(apple: appleCredential)
        fixture.auth.sessionDidExpire()
        #expect(!fixture.auth.isSignedIn)
        #expect(fixture.harness.count(Connection.self) == 6)
    }

    @Test("Mock mode with demo data on the device starts signed in")
    func mockDemoSession() throws {
        let fixture = try Fixture(local: .full, server: .demo, isMock: true)
        #expect(fixture.auth.isSignedIn)
        #expect(fixture.auth.accountEmail == MockSeed.ownerEmail)
    }

    @Test func missingIdentityToken() async throws {
        let fixture = try Fixture(server: .newAccount)
        let credential = AppleSignInCredential(userID: "x", identityToken: nil, authorizationCode: nil, fullName: nil, email: nil)
        await #expect(throws: AuthError.missingIdentityToken) { _ = try await fixture.auth.signIn(apple: credential) }
    }
}

@MainActor
@Suite("MetlyClient", .timeLimit(.minutes(1)))
struct MetlyClientTests {
    private func makeClient(local: PreviewSeed.Variant = .full) throws -> (MetlyClient, SyncHarness) {
        let harness = try SyncHarness(local: local, server: .demo)
        let client = MetlyClient(api: harness.server, container: harness.container, mockServer: harness.server)
        client.startRealtime()
        return (client, harness)
    }

    /// Waits until the realtime channel is up (the mock accepts within 40 ms in tests).
    private func connected(_ client: MetlyClient) async {
        while client.realtimeState != .connected { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test("Connect: the mock peer accepts and the connection is already saved")
    func connectAccepted() async throws {
        let (client, harness) = try makeClient()
        await connected(client)
        let request = try await client.sendConnectRequest(to: .nearbyToken("mock-peer-sardor"), cardID: MockSeed.workCardID,
                                                          method: .nearby)
        let outcome = await client.outcome(of: request)
        guard case .accepted(let connectionID) = outcome else {
            Issue.record("Expected accepted, got \(outcome)")
            return
        }
        let connection = try #require(harness.connection(connectionID))
        #expect(connection.remoteUserID == MockSeed.peer(token: "mock-peer-sardor")?.userID)
        // Sardor already was a connection in the demo data → updated, not duplicated.
        #expect(connectionID == MockSeed.connectionIDs[1])
        #expect(harness.count(Connection.self) == 6)
        #expect(harness.context.record(ConnectRequest.self, id: request.id)?.status == .accepted)
    }

    @Test("Connect: no answer → .noResponse")
    func connectNoResponse() async throws {
        let (client, _) = try makeClient()
        let request = try await client.sendConnectRequest(to: .slug("nodira-n5m1"), cardID: MockSeed.workCardID, method: .scan)
        #expect(await client.outcome(of: request) == .noResponse)
    }

    @Test("Accepting an incoming request returns the new connection")
    func acceptIncoming() async throws {
        let (client, harness) = try makeClient()
        let request = try #require(harness.context.record(ConnectRequest.self, id: MockSeed.incomingRequestID))
        let connection = try #require(try await client.accept(request, sharing: MockSeed.workCardID))
        #expect(connection.fullName == "Bekzod Tursunov")
        #expect(request.status == .accepted)
        #expect(try harness.context.fetch(ConnectRequest.pendingIncoming).isEmpty)
    }

    @Test("Accept while offline is queued for sync")
    func acceptOfflineQueues() async throws {
        let (client, harness) = try makeClient()
        await harness.server.setReachable(false)
        let request = try #require(harness.context.record(ConnectRequest.self, id: MockSeed.incomingRequestID))
        let connection = try await client.accept(request, sharing: MockSeed.workCardID)
        #expect(connection == nil)
        #expect(request.status == .accepted)
        #expect(request.syncState == .pendingUpsert)
    }

    @Test("Realtime incoming requests land in SwiftData and on the event stream")
    func realtimeIncoming() async throws {
        let (client, harness) = try makeClient(local: .empty)
        let stream = client.events()   // subscribed before the realtime task runs
        var simulated: ConnectRequestDTO?
        for await event in stream {
            switch event {
            case .stateChanged(.connected):
                simulated = await harness.server.simulateIncomingRequest(fromSlug: "kamila-x1y2")
            case .requestReceived(let request):
                #expect(request.id == simulated?.id)
            default:
                continue
            }
            if case .requestReceived = event { break }
        }
        #expect(client.realtimeState == .connected)
        #expect(harness.context.record(ConnectRequest.self, id: try #require(simulated?.id))?.peerName == "Kamila Yusupova")
    }

    @Test("Publishing writes the server slug back to the card")
    func publish() async throws {
        let (client, harness) = try makeClient()
        let card = try #require(harness.context.record(Card.self, id: MockSeed.personalCardID))
        card.name = "Weekend"
        card.markChanged()
        try await client.publish(card)
        #expect(card.syncState == .synced)
        #expect(card.slug == "aziza-p3x9")
        #expect(await harness.server.liveRecords().cards.first { $0.id == card.id }?.name == "Weekend")
    }

    @Test func walletPassPlaceholder() async throws {
        let (client, harness) = try makeClient()
        let card = try #require(harness.context.defaultCard())
        await #expect(throws: APIError.serverRequired("Wallet passes need the server.")) { _ = try await client.walletPass(for: card) }
    }

    @Test func publicProfileSnapshot() async throws {
        let (client, _) = try makeClient()
        let profile = try await client.publicProfile(slug: "bekzod-b8n3")
        #expect(profile.snapshot?.fullName == "Bekzod Tursunov")
        #expect(client.demoNearbyTokens.contains("mock-peer-kamila"))
    }

    @Test("Factory: makeServices and makeClient share one graph per container")
    func factorySharesGraph() throws {
        let container = try MetlyModelContainer.make(inMemory: true)
        let services = MetlyServiceFactory.makeServices(container: container)
        let client = MetlyServiceFactory.makeClient(container: container)
        let environment = MetlyServiceFactory.makeEnvironment(container: container)
        #expect(environment.services === services)
        #expect(environment.client === client)
        #expect(services.sync as AnyObject === environment.syncEngine)
    }
}
