import Foundation
import MetlyCore

/// In-memory stand-in for the backend until it exists (used whenever `MetlyAPIBaseURL` is unset).
///
/// - ~300 ms latency per call, `setReachable(false)` simulates an outage.
/// - Seeded from `MockSeed` (Aziza Karimova + people), so it agrees with `PreviewSeed` record ids.
/// - Publishing assigns `{firstname}-{4}` slugs; public profiles exist for `kamila-x1y2`, `sardor-r4t5`,
///   `bekzod-b8n3`, `nodira-n5m1` (never answers) and `lola-p0z3` (paused).
/// - Outgoing connect requests are accepted by the peer after ~1.6 s, or expire (Nodira) — both
///   delivered on `realtime.connectEvents()`.
/// - Wallet passes throw `APIError.serverRequired("Wallet passes need the server.")`.
public actor MockMetlyServer: MetlyAPI {
    public struct Configuration: Sendable {
        public var latency: Duration
        public var connectAcceptDelay: Duration
        public var connectRequestLifetime: Duration
        /// Simulated incoming Nearby / Tap Phones requests expire after this (60 s like the server).
        public var incomingLiveRequestLifetime: Duration
        /// DEFERRED_WELCOME: `claim` returns an invite only when true (`-MetlyDeferredInvite`).
        public var deferredInviteEnabled: Bool

        public init(latency: Duration = .milliseconds(300), connectAcceptDelay: Duration = .milliseconds(1600),
                    connectRequestLifetime: Duration = .seconds(8), incomingLiveRequestLifetime: Duration = .seconds(60),
                    deferredInviteEnabled: Bool = ProcessInfo.processInfo.arguments.contains("-MetlyDeferredInvite")) {
            self.latency = latency
            self.connectAcceptDelay = connectAcceptDelay
            self.connectRequestLifetime = connectRequestLifetime
            self.incomingLiveRequestLifetime = incomingLiveRequestLifetime
            self.deferredInviteEnabled = deferredInviteEnabled
        }

        public static var standard: Configuration { Configuration() }
        /// No latency, fast connect timers — for unit tests.
        public static var instant: Configuration {
            Configuration(latency: .zero, connectAcceptDelay: .milliseconds(40), connectRequestLifetime: .milliseconds(250),
                          incomingLiveRequestLifetime: .milliseconds(250), deferredInviteEnabled: false)
        }
    }

    public enum Seed: Sendable {
        /// No account yet: signing in creates a new user who goes through setup.
        case newAccount
        /// The demo account (`MockSeed.demoAccount()`), signed in and set up.
        case demo
        /// Mirror an existing device store (built by MetlyData from SwiftData).
        case account(MockSeed.Account)
    }

    public nonisolated let configuration: Configuration
    private var backend: MockBackend
    private var subscribers: [UUID: AsyncStream<ConnectEvent>.Continuation] = [:]
    private var timers: [UUID: Task<Void, Never>] = [:]
    public private(set) var isReachable = true
    /// False = no object storage configured: image uploads answer `503 service_unavailable`.
    public private(set) var hasImageStorage = true
    /// Number of API calls served (tests/diagnostics).
    public private(set) var callCount = 0

    public init(seed: Seed = .demo, configuration: Configuration = .standard, isReachable: Bool = true) {
        self.configuration = configuration
        self.isReachable = isReachable
        switch seed {
        case .newAccount: backend = MockBackend()
        case .demo: backend = MockBackend(account: MockSeed.demoAccount())
        case .account(let account): backend = MockBackend(account: account)
        }
    }

    public nonisolated var auth: any AuthAPI { self }
    public nonisolated var account: any AccountAPI { self }
    public nonisolated var profile: any ProfileAPI { self }
    public nonisolated var cards: any CardsAPI { self }
    public nonisolated var wallet: any WalletAPI { self }
    public nonisolated var connections: any ConnectionsAPI { self }
    public nonisolated var blocks: any BlocksAPI { self }
    public nonisolated var followUps: any FollowUpsAPI { self }
    public nonisolated var events: any EventsAPI { self }
    public nonisolated var connect: any ConnectAPI { self }
    public nonisolated var realtime: any RealtimeAPI { self }
    public nonisolated var publicProfiles: any PublicProfilesAPI { self }
    public nonisolated var deferredLinks: any DeferredLinksAPI { self }
    public nonisolated var subscriptions: any SubscriptionsAPI { self }
    public nonisolated var devices: any DevicesAPI { self }
    public nonisolated var sync: any SyncAPI { self }

    // MARK: Simulation controls (previews, tests, DEBUG menus)

    public func setReachable(_ reachable: Bool) { isReachable = reachable }

    public func setImageStorage(_ available: Bool) { hasImageStorage = available }

    /// Every live record the server holds.
    public func liveRecords() -> SyncChanges {
        (try? backend.pull(since: nil, limit: .max, now: .now).changes) ?? SyncChanges()
    }

    public var tombstoneIDs: Set<UUID> { Set(backend.tombstones.keys) }
    public var plan: Plan { backend.entitlement.plan }

    /// Applies changes as if another device pushed them (LWW applies) and notifies listeners.
    @discardableResult
    public func simulateRemoteChanges(_ changes: SyncChanges) -> SyncPushResponse {
        let response = backend.push(changes, now: .now)
        broadcast(.syncAvailable)
        return response
    }

    /// "Bekzod wants to connect" — creates an incoming request and emits `.requestReceived`.
    @discardableResult
    public func simulateIncomingRequest(fromSlug slug: String = "bekzod-b8n3", method: ConnectMethod = .nearby) -> ConnectRequestDTO? {
        guard let peer = MockSeed.peer(slug: slug) else { return nil }
        let lifetime = configuration.incomingLiveRequestLifetime
        let request = backend.createIncomingRequest(from: peer, method: method, liveLifetime: lifetime.seconds, now: .now)
        broadcast(.requestReceived(request))
        if MockBackend.isLive(method) {
            // Nobody answered in time: the request expires (INCOMING_REQUEST must handle it).
            timers[request.id] = Task { [weak self] in
                do { try await Task.sleep(for: lifetime) } catch { return }
                await self?.expireIncoming(request.id)
            }
        }
        return request
    }

    private func expireIncoming(_ requestID: UUID) {
        timers[requestID] = nil
        guard let request = try? backend.setStatus(.expired, requestID: requestID, expected: .incoming, now: .now) else { return }
        broadcast(.requestUpdated(request, connection: nil))
    }

    /// A web visitor shares their contact back (SPEC §3.10 merge rules) and emits `.shareBackReceived`.
    @discardableResult
    public func simulateShareBack(name: String, phone: String? = nil, telegram: String? = nil, metAt: String? = nil,
                                  cardID: UUID? = nil) -> ShareBackNoticeDTO {
        let notice = backend.receiveShareBack(name: name, phone: phone, telegram: telegram, metAtText: metAt, cardID: cardID, now: .now)
        broadcast(.shareBackReceived(notice))
        return notice
    }

    /// The connected Nameshake user changed their profile photo: sets the server-owned `avatarUrl` of
    /// connection `id` (nil `data` removes it) and emits `.syncAvailable`. Returns the asset URL.
    @discardableResult
    public func simulateAvatar(connectionID id: UUID, data: Data?) -> URL? {
        guard var connection = backend.connections[id] else { return nil }
        if let previous = connection.avatarURL { backend.assets[previous] = nil }
        let url = data.map { _ in URL(string: "https://assets.mock.tanishly.app/avatar/\(UUID().uuidString.lowercased()).jpg")! }
        if let url, let data { backend.assets[url] = data }
        connection.avatarURL = url
        backend.connections[id] = connection
        backend.touch(.connection, id)
        broadcast(.syncAvailable)
        return url
    }

    // MARK: Plumbing

    private func serve() async throws {
        callCount += 1
        if configuration.latency > .zero {
            do { try await Task.sleep(for: configuration.latency) } catch { throw APIError.cancelled }
        }
        guard isReachable else { throw APIError.offline }
    }

    private func broadcast(_ event: ConnectEvent) {
        for continuation in subscribers.values { continuation.yield(event) }
    }

    private func removeSubscriber(_ id: UUID) { subscribers[id] = nil }

    /// REST flavour of a sync upsert: 200 with the canonical record, 403/422 on rejection, 410 if deleted.
    private func rest<T>(_ result: SyncResultDTO, _ canonical: SyncChanges, _ pick: (SyncChanges) -> T?) throws -> T {
        if result.status == .rejected {
            let status = result.error?.knownCode == .validationFailed ? 422 : 403
            throw APIError.server(status: status, problem: result.error)
        }
        if let value = pick(canonical) { return value }
        throw APIError.mock(410, .gone, "This record was deleted.")
    }

    private func tombstone(_ type: SyncRecordType, _ id: UUID) {
        var canonical = SyncChanges()
        _ = backend.delete(TombstoneDTO(type: type, id: id, deletedAt: .now), canonical: &canonical)
    }

    private func schedule(_ requestID: UUID, behavior: MockSeed.Peer.Behavior) {
        let delay = behavior == .accepts ? configuration.connectAcceptDelay : configuration.connectRequestLifetime
        timers[requestID] = Task { [weak self] in
            do { try await Task.sleep(for: delay) } catch { return }
            await self?.resolveOutgoing(requestID, behavior: behavior)
        }
    }

    private func resolveOutgoing(_ requestID: UUID, behavior: MockSeed.Peer.Behavior) {
        timers[requestID] = nil
        guard backend.requests[requestID]?.status == .pending else { return }
        let now = Date.now
        switch behavior {
        case .accepts:
            if let response = try? backend.completeRequest(id: requestID, myCardID: nil, now: now) {
                broadcast(.requestUpdated(response.request, connection: response.connection))
            }
        case .ignores:
            if let request = try? backend.setStatus(.expired, requestID: requestID, expected: .outgoing, now: now) {
                broadcast(.requestUpdated(request, connection: nil))
            }
        }
    }
}

// MARK: - Auth & account

extension MockMetlyServer: AuthAPI, AccountAPI {
    public func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse {
        try await serve()
        guard !request.identityToken.isEmpty else { throw APIError.mock(400, .invalidRequest, "identityToken is required.") }
        return backend.signIn(provider: .apple, email: request.email, suggestedName: request.fullName?.formatted, now: .now)
    }

    public func signInWithGoogle(_ request: GoogleSignInRequest) async throws -> AuthResponse {
        try await serve()
        guard !request.idToken.isEmpty else { throw APIError.mock(400, .invalidRequest, "idToken is required.") }
        return backend.signIn(provider: .google, email: nil, suggestedName: nil, now: .now)
    }

    public func signInWithTelegram(_ request: TelegramSignInRequest) async throws -> AuthResponse {
        try await serve()
        guard !request.code.isEmpty else { throw APIError.mock(400, .invalidRequest, "code is required.") }
        return backend.signIn(provider: .telegram, email: nil, suggestedName: nil, now: .now)
    }

    /// No backend to send the browser to: the app's DEBUG path signs in with a mock code instead.
    public nonisolated func telegramAuthorizationURL(codeChallenge: String, state: String, nonce: String) -> URL? { nil }

    public func logout(_ request: LogoutRequest) async throws { try await serve() }

    public func fetchMe() async throws -> MeResponse {
        try await serve()
        guard let user = backend.user else { throw APIError.unauthorized }
        return MeResponse(user: user, profile: backend.profile, entitlement: backend.entitlement)
    }

    public func deleteAccount() async throws {
        try await serve()
        for timer in timers.values { timer.cancel() }
        timers = [:]
        backend.deleteAccount()
    }

    public func requestDataExport() async throws -> DataExportResponse {
        try await serve()
        return DataExportResponse(requestedAt: .now, email: backend.user?.email)
    }
}

// MARK: - Profile

extension MockMetlyServer: ProfileAPI {
    public func fetchProfile() async throws -> ProfileDTO {
        try await serve()
        guard let profile = backend.profile else { throw APIError.notFound("Profile") }
        return profile
    }

    public func updateProfile(_ profile: ProfileDTO) async throws -> ProfileDTO {
        try await serve()
        var canonical = SyncChanges()
        let result = backend.upsertProfile(profile, canonical: &canonical)
        return try rest(result, canonical) { $0.profile }
    }

    public func fetchSettings() async throws -> SettingsDTO {
        try await serve()
        guard let profile = backend.profile else { throw APIError.notFound("Profile") }
        return SettingsDTO(notificationPrefs: profile.notificationPrefs, privacySettings: profile.privacySettings,
                           linksPaused: profile.linksPaused, defaultCardID: profile.defaultCardID, updatedAt: profile.updatedAt)
    }

    public func updateSettings(_ patch: SettingsPatch) async throws -> SettingsDTO {
        try await serve()
        guard var profile = backend.profile else { throw APIError.notFound("Profile") }
        if let value = patch.notificationPrefs { profile.notificationPrefs = value }
        if let value = patch.privacySettings { profile.privacySettings = value }
        if let value = patch.linksPaused { profile.linksPaused = value }
        if let value = patch.defaultCardID { profile.defaultCardID = value }
        profile.updatedAt = patch.updatedAt
        var canonical = SyncChanges()
        let result = backend.upsertProfile(profile, canonical: &canonical)
        let stored = try rest(result, canonical) { $0.profile }
        return SettingsDTO(notificationPrefs: stored.notificationPrefs, privacySettings: stored.privacySettings,
                           linksPaused: stored.linksPaused, defaultCardID: stored.defaultCardID, updatedAt: stored.updatedAt)
    }

    public func requestImageUpload(_ kind: ProfileImageKind, _ request: UploadTicketRequest) async throws -> UploadTicket {
        try await serve()
        guard hasImageStorage else { throw APIError.mock(503, .serviceUnavailable, "Image uploads are not available right now.") }
        guard request.byteSize <= 5_000_000 else { throw APIError.mock(413, .payloadTooLarge, "Images must be 5 MB or smaller.") }
        let id = "up_\(UUID().uuidString.lowercased())"
        return UploadTicket(uploadID: id, uploadURL: URL(string: "https://uploads.mock.tanishly.app/\(id)")!,
                            headers: ["Content-Type": request.contentType], expiresAt: .now.addingTimeInterval(900))
    }

    public func upload(_ data: Data, using ticket: UploadTicket) async throws {
        try await serve()
        backend.pendingUploads[ticket.uploadID] = data
    }

    public func commitImageUpload(_ kind: ProfileImageKind, uploadID: String) async throws -> ProfileDTO {
        try await serve()
        guard let data = backend.pendingUploads.removeValue(forKey: uploadID) else { throw APIError.notFound("Upload") }
        guard var profile = backend.profile else { throw APIError.notFound("Profile") }
        let url = URL(string: "https://assets.mock.tanishly.app/\(kind.rawValue)/\(UUID().uuidString.lowercased()).jpg")!
        backend.assets[url] = data
        switch kind {
        case .photo: profile.photoURL = url
        case .logo: profile.logoURL = url
        }
        backend.profile = profile
        backend.touch(.profile, profile.id)
        return profile
    }

    public func deleteImage(_ kind: ProfileImageKind) async throws -> ProfileDTO {
        try await serve()
        guard var profile = backend.profile else { throw APIError.notFound("Profile") }
        switch kind {
        case .photo: profile.photoURL = nil
        case .logo: profile.logoURL = nil
        }
        backend.profile = profile
        backend.touch(.profile, profile.id)
        return profile
    }

    public func downloadAsset(_ url: URL) async throws -> Data {
        try await serve()
        guard let data = backend.assets[url] else { throw APIError.notFound("Asset") }
        return data
    }
}

// MARK: - Cards & Wallet

extension MockMetlyServer: CardsAPI, WalletAPI {
    public func listCards() async throws -> [CardDTO] {
        try await serve()
        return backend.cards.values.sorted { $0.sortOrder < $1.sortOrder }
    }

    public func fetchCard(id: UUID) async throws -> CardDTO {
        try await serve()
        guard let card = backend.cards[id] else { throw APIError.notFound("Card") }
        return card
    }

    public func upsertCard(_ card: CardDTO) async throws -> CardDTO {
        try await serve()
        var canonical = SyncChanges()
        let result = backend.upsertCard(card, now: .now, canonical: &canonical)
        return try rest(result, canonical) { $0.cards.first }
    }

    public func publishCard(_ card: CardDTO) async throws -> CardDTO {
        try await upsertCard(card)
    }

    public func deleteCard(id: UUID) async throws {
        try await serve()
        tombstone(.card, id)
    }

    public func duplicateCard(id: UUID, _ request: DuplicateCardRequest) async throws -> CardDTO {
        try await serve()
        return try backend.duplicateCard(id: id, request, now: .now)
    }

    public func reorderCards(_ request: ReorderCardsRequest) async throws -> [CardDTO] {
        try await serve()
        return backend.reorderCards(request.cardIDs, now: .now)
    }

    public func cardStats(id: UUID) async throws -> CardStatsDTO {
        try await serve()
        return try backend.stats(cardID: id, now: .now)
    }

    public func walletPass(cardID: UUID) async throws -> Data {
        try await serve()
        throw APIError.serverRequired("Wallet passes need the server.")
    }
}

// MARK: - Connections & blocks

extension MockMetlyServer: ConnectionsAPI, BlocksAPI {
    public func listConnections(updatedSince: Date?, cursor: String?, limit: Int) async throws -> Page<ConnectionDTO> {
        try await serve()
        let items = backend.connections.values
            .filter { updatedSince == nil || $0.updatedAt > updatedSince! }
            .sorted { $0.updatedAt < $1.updatedAt }
        return MockBackend.page(items, cursor: cursor, limit: limit)
    }

    public func upsertConnection(_ connection: ConnectionDTO) async throws -> ConnectionDTO {
        try await serve()
        var canonical = SyncChanges()
        let result = backend.upsertConnection(connection, canonical: &canonical)
        return try rest(result, canonical) { $0.connections.first }
    }

    public func deleteConnection(id: UUID) async throws {
        try await serve()
        tombstone(.connection, id)
    }

    public func blockConnection(id: UUID) async throws -> ConnectionDTO {
        try await serve()
        guard var connection = backend.connections[id] else { throw APIError.notFound("Connection") }
        connection.isBlocked = true
        connection.updatedAt = .now
        var canonical = SyncChanges()
        let result = backend.upsertConnection(connection, canonical: &canonical)
        if let userID = connection.remoteUserID {
            backend.blocks[userID] = BlockDTO(userID: userID, connectionID: id, fullName: connection.fullName, blockedAt: .now)
        }
        return try rest(result, canonical) { $0.connections.first }
    }

    public func listBlocks() async throws -> [BlockDTO] {
        try await serve()
        var blocks = backend.blocks
        for connection in backend.connections.values where connection.isBlocked {
            let key = connection.remoteUserID ?? connection.id
            if blocks[key] == nil {
                blocks[key] = BlockDTO(userID: connection.remoteUserID, connectionID: connection.id,
                                       fullName: connection.fullName, blockedAt: connection.updatedAt)
            }
        }
        return blocks.values.sorted { $0.blockedAt > $1.blockedAt }
    }

    public func block(_ request: BlockRequest) async throws -> BlockDTO {
        if let connectionID = request.connectionID {
            let connection = try await blockConnection(id: connectionID)
            return BlockDTO(userID: connection.remoteUserID, connectionID: connectionID, fullName: connection.fullName, blockedAt: .now)
        }
        try await serve()
        guard let userID = request.userID else { throw APIError.mock(422, .validationFailed, "userId or connectionId is required.") }
        let block = BlockDTO(userID: userID, connectionID: nil, fullName: MockSeed.peer(userID: userID)?.fullName ?? "Nameshake user",
                             blockedAt: .now)
        backend.blocks[userID] = block
        return block
    }

    public func unblock(userID: UUID) async throws {
        try await serve()
        backend.blocks[userID] = nil
        for connection in backend.connections.values where connection.remoteUserID == userID && connection.isBlocked {
            var updated = connection
            updated.isBlocked = false
            updated.updatedAt = .now
            var canonical = SyncChanges()
            _ = backend.upsertConnection(updated, canonical: &canonical)
        }
    }
}

// MARK: - Follow-ups & events

extension MockMetlyServer: FollowUpsAPI, EventsAPI {
    public func listFollowUps(cursor: String?, limit: Int) async throws -> Page<FollowUpDTO> {
        try await serve()
        return MockBackend.page(backend.followUps.values.sorted { $0.dueAt < $1.dueAt }, cursor: cursor, limit: limit)
    }

    public func upsertFollowUp(_ followUp: FollowUpDTO) async throws -> FollowUpDTO {
        try await serve()
        var canonical = SyncChanges()
        let result = backend.upsertFollowUp(followUp, canonical: &canonical)
        return try rest(result, canonical) { $0.followUps.first }
    }

    public func deleteFollowUp(id: UUID) async throws {
        try await serve()
        tombstone(.followUp, id)
    }

    public func bulkUpsertFollowUps(_ followUps: [FollowUpDTO]) async throws -> [FollowUpDTO] {
        try await serve()
        if let max = backend.limits.maxOpenFollowUps {
            let open = backend.followUps.values.filter { !$0.isDone }.count
            let opening = followUps.filter { !$0.isDone && backend.followUps[$0.id].map(\.isDone) != false }.count
            if open + opening > max {
                throw APIError.mock(403, .planLimitReached, "The Free plan includes \(max) active reminders.", details: ["limit": "\(max)"])
            }
        }
        var canonical = SyncChanges()
        for followUp in followUps { _ = backend.upsertFollowUp(followUp, canonical: &canonical) }
        return canonical.followUps
    }

    public func listEvents() async throws -> [EventDTO] {
        try await serve()
        return backend.events.values.sorted { $0.startDate > $1.startDate }
    }

    public func upsertEvent(_ event: EventDTO) async throws -> EventDTO {
        try await serve()
        var canonical = SyncChanges()
        let result = backend.upsertEvent(event, canonical: &canonical)
        return try rest(result, canonical) { $0.events.first }
    }

    public func deleteEvent(id: UUID) async throws {
        try await serve()
        tombstone(.event, id)
    }

    public func endEvent(id: UUID) async throws -> EventDTO {
        try await serve()
        return try backend.setEventStatus(id: id, active: false, now: .now)
    }

    public func resumeEvent(id: UUID) async throws -> EventDTO {
        try await serve()
        return try backend.setEventStatus(id: id, active: true, now: .now)
    }

    public func eventSummary(id: UUID) async throws -> EventSummaryDTO {
        try await serve()
        return try backend.summary(eventID: id)
    }
}

// MARK: - Connect & realtime

extension MockMetlyServer: ConnectAPI, RealtimeAPI {
    public func startSession(_ request: ConnectSessionRequest) async throws -> ConnectSessionDTO {
        try await serve()
        return ConnectSessionDTO(sessionID: "cs_\(UUID().uuidString.lowercased())",
                                 discoveryToken: "mock-self-\(UUID().uuidString.prefix(8).lowercased())",
                                 expiresAt: .now.addingTimeInterval(600))
    }

    public func endSession(id: String) async throws { try await serve() }

    public func resolvePeers(tokens: [String]) async throws -> [NearbyPeerDTO] {
        try await serve()
        let blocked = Set(backend.blocks.keys)
        return tokens.compactMap(MockSeed.peer(token:)).filter { !$0.isPaused && !blocked.contains($0.userID) }.map(\.nearby)
    }

    public func sendRequest(_ request: SendConnectRequest) async throws -> ConnectRequestDTO {
        try await serve()
        let peer = try backend.peer(for: request)
        let now = Date.now
        let outgoing = backend.createOutgoingRequest(request, peer: peer, lifetime: configuration.connectRequestLifetime.seconds, now: now)
        // Requests to someone the owner blocked are dropped silently: they just expire ("no response").
        let blocked = backend.blocks[peer.userID] != nil
            || backend.connections.values.contains { $0.remoteUserID == peer.userID && $0.isBlocked }
        if request.method == .deferred, !blocked {
            // Deferred-link connects are pre-approved by the owner sharing their card.
            let response = try backend.completeRequest(id: outgoing.id, myCardID: request.cardID, now: now)
            broadcast(.requestUpdated(response.request, connection: response.connection))
            return response.request
        }
        schedule(outgoing.id, behavior: blocked ? .ignores : peer.behavior)
        return outgoing
    }

    public func listRequests(status: ConnectRequestStatus?, direction: ConnectRequestDirection?) async throws -> [ConnectRequestDTO] {
        try await serve()
        return backend.requests.values
            .filter { (status == nil || $0.status == status) && (direction == nil || $0.direction == direction) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    public func fetchRequest(id: UUID) async throws -> ConnectRequestDTO {
        try await serve()
        guard let request = backend.requests[id] else { throw APIError.notFound("Request") }
        return request
    }

    public func acceptRequest(id: UUID, _ request: AcceptConnectRequest) async throws -> ConnectAcceptResponse {
        try await serve()
        guard backend.requests[id]?.direction == .incoming else { throw APIError.notFound("Request") }
        let response = try backend.completeRequest(id: id, myCardID: request.cardID, now: .now)
        timers.removeValue(forKey: id)?.cancel()
        return response
    }

    public func declineRequest(id: UUID) async throws -> ConnectRequestDTO {
        try await serve()
        let request = try backend.setStatus(.declined, requestID: id, expected: .incoming, now: .now)
        timers.removeValue(forKey: id)?.cancel()
        return request
    }

    public func cancelRequest(id: UUID) async throws -> ConnectRequestDTO {
        try await serve()
        timers.removeValue(forKey: id)?.cancel()
        return try backend.setStatus(.cancelled, requestID: id, expected: .outgoing, now: .now)
    }

    public func connectEvents() async -> AsyncStream<ConnectEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectEvent.self, bufferingPolicy: .bufferingNewest(64))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id) }
        }
        continuation.yield(.stateChanged(.connected))
        return stream
    }
}

// MARK: - Public profiles, deferred links, subscriptions, devices, sync

extension MockMetlyServer: PublicProfilesAPI, DeferredLinksAPI, SubscriptionsAPI, DevicesAPI, SyncAPI {
    public func publicProfile(slug: String) async throws -> PublicCardDTO {
        try await serve()
        return try backend.publicCard(slug: slug)
    }

    public func claim(_ request: DeferredLinkClaimRequest) async throws -> DeferredInviteDTO? {
        try await serve()
        return configuration.deferredInviteEnabled ? MockSeed.deferredInvite() : nil
    }

    public func verify(_ request: VerifyTransactionRequest) async throws -> EntitlementDTO {
        try await serve()
        return backend.verify(request.signedTransaction, now: .now)
    }

    public func fetchEntitlement() async throws -> EntitlementDTO {
        try await serve()
        return backend.entitlement
    }

    public func registerDevice(_ request: DeviceRegistrationRequest) async throws {
        try await serve()
        backend.devices[request.deviceID] = request
    }

    public func unregisterDevice(id: String) async throws {
        try await serve()
        backend.devices[id] = nil
    }

    public func push(_ request: SyncPushRequest) async throws -> SyncPushResponse {
        try await serve()
        return backend.push(request.changes, now: .now)
    }

    public func pull(since cursor: String?, limit: Int) async throws -> SyncPullResponse {
        try await serve()
        return try backend.pull(since: cursor, limit: limit, now: .now)
    }
}
