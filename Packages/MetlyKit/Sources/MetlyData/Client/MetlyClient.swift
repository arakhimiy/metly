import Foundation
import MetlyCore
import MetlyNetworking
import Observation
import SwiftData

/// Who to send a connect request to.
public enum ConnectTarget: Sendable, Hashable {
    /// A discovery token seen over Nearby / Tap Phones.
    case nearbyToken(String)
    case user(UUID)
    /// A scanned `metly.link/c/{slug}`.
    case slug(String)
}

/// How an outgoing connect request ended (the requester never learns about a decline — SPEC §9 Q9).
public enum ConnectOutcome: Sendable, Hashable {
    /// Both sides are connected; route to `.connected(connectionID:)`.
    case accepted(connectionID: UUID)
    /// Declined, expired or timed out → "{first} didn't respond. They may have closed Connect."
    case noResponse
    /// The request was cancelled (or the waiting task was).
    case cancelled
}

/// Server access for features. Inject at the root with `.environment(client)` and read with
/// `@Environment(MetlyClient.self) private var client`.
///
/// Use the model-aware helpers below for server-only actions (they keep SwiftData in step);
/// `api` exposes every raw endpoint. Plain CRUD needs no API call at all: mutate the model,
/// call `markChanged()` and the sync engine pushes it.
@MainActor
@Observable
public final class MetlyClient {
    /// Every endpoint, grouped (`client.api.cards.cardStats(id:)`…).
    @ObservationIgnored public let api: any MetlyAPI
    /// Non-nil when running against the in-memory mock (no backend configured, previews, tests).
    @ObservationIgnored public let mockServer: MockMetlyServer?
    public private(set) var realtimeState: RealtimeState = .disconnected

    @ObservationIgnored private let container: ModelContainer
    @ObservationIgnored private var subscribers: [UUID: AsyncStream<ConnectEvent>.Continuation] = [:]
    @ObservationIgnored private var realtimeTask: Task<Void, Never>?
    /// Wired by the factory to `SyncEngine.requestSync()`.
    @ObservationIgnored var onSyncHint: () -> Void = {}

    public init(api: any MetlyAPI, container: ModelContainer, mockServer: MockMetlyServer? = nil) {
        self.api = api
        self.container = container
        self.mockServer = mockServer
    }

    public var isMock: Bool { mockServer != nil }

    // MARK: Realtime

    /// Live connect / share-back events. Each call returns an independent stream; iterate it in
    /// `.task {}` so it ends with the view. Records are already saved to SwiftData when an event
    /// arrives (incoming requests, accepted connections, share-backs).
    public func events() -> AsyncStream<ConnectEvent> {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectEvent.self, bufferingPolicy: .bufferingNewest(32))
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.subscribers[id] = nil }
        }
        return stream
    }

    /// Opens the realtime channel (done automatically while signed in).
    public func startRealtime() {
        guard realtimeTask == nil else { return }
        let api = api
        realtimeTask = Task { [weak self] in
            let stream = await api.realtime.connectEvents()
            for await event in stream {
                guard let self else { return }
                self.handle(event)
            }
        }
    }

    public func stopRealtime() {
        realtimeTask?.cancel()
        realtimeTask = nil
        realtimeState = .disconnected
    }

    private func handle(_ event: ConnectEvent) {
        let context = container.mainContext
        var applier = SyncApplier(context: context, mode: .pull)
        switch event {
        case .requestReceived(let request):
            applier.apply(request)
        case .requestUpdated(let request, let connection):
            if let connection { applier.apply(connection) }
            applier.apply(request)
        case .shareBackReceived(let notice):
            applier.apply(notice.connection)
        case .syncAvailable:
            onSyncHint()
        case .stateChanged(let state):
            realtimeState = state
        }
        try? context.save()
        for continuation in subscribers.values { continuation.yield(event) }
    }

    // MARK: Cards

    /// Publishes now (CARD_CREATE "Publish", Editor "Done") and writes the server's slug back.
    /// On failure the card stays a local draft and the sync engine publishes it when online —
    /// show ALERT_PUBLISH_FAILED and move on.
    public func publish(_ card: Card) async throws {
        let context = container.mainContext
        // The slug is derived from the profile name, so the profile must reach the server first.
        if let profile = context.currentProfile(), profile.syncState != .synced {
            let sentAt = profile.updatedAt
            let canonical = try await api.profile.updateProfile(profile.dto)
            if profile.updatedAt == sentAt {
                profile.apply(canonical)
                profile.syncState = .synced
            }
        }
        let sentAt = card.updatedAt
        let canonical = try await api.cards.publishCard(card.dto)
        if card.updatedAt == sentAt {
            card.apply(canonical)
            card.syncState = .synced
        } else {
            card.applyServerOwned(canonical)
        }
        try? context.save()
    }

    /// Signed `.pkpass` for `PKAddPassesViewController`. The mock throws
    /// `APIError.serverRequired("Wallet passes need the server.")`.
    public func walletPass(for card: Card) async throws -> Data {
        try await api.wallet.walletPass(cardID: card.id)
    }

    /// Fresh Viewed / Saved / Shared back numbers, also stored on `card.stats`.
    @discardableResult
    public func refreshStats(for card: Card) async throws -> CardStatsDTO {
        let stats = try await api.cards.cardStats(id: card.id)
        card.stats = stats.stats
        try? container.mainContext.save()
        return stats
    }

    // MARK: Public profiles (SCANNED_CARD)

    /// The card behind a scanned `metly.link/c/{slug}`; `status != .available` → show the
    /// "This card isn't available right now." state. `snapshot` feeds `CardFaceView`.
    public func publicProfile(slug: String) async throws -> PublicCardDTO {
        try await api.publicProfiles.publicProfile(slug: slug)
    }

    // MARK: Connect

    /// Discovery tokens of the mock world's people (simulator has no Nearby peers). Empty live.
    public var demoNearbyTokens: [String] { isMock ? MockSeed.nearbyTokens : [] }

    public func startConnectSession(cardID: UUID, eventID: UUID? = nil, method: ConnectMethod = .nearby) async throws -> ConnectSessionDTO {
        try await api.connect.startSession(ConnectSessionRequest(cardID: cardID, eventID: eventID, method: method))
    }

    public func endConnectSession(_ sessionID: String) async {
        try? await api.connect.endSession(id: sessionID)
    }

    public func resolvePeers(tokens: [String]) async throws -> [NearbyPeerDTO] {
        try await api.connect.resolvePeers(tokens: tokens)
    }

    /// Sends a request (Connect "Waiting…"); then `await outcome(of:)`.
    public func sendConnectRequest(to target: ConnectTarget, cardID: UUID, method: ConnectMethod) async throws -> ConnectRequestDTO {
        let context = container.mainContext
        let event = context.activeEvent()
        var body = SendConnectRequest(cardID: cardID, method: method, eventID: event?.id, eventName: event?.name,
                                      place: event.map { [$0.place, $0.city].filter { !$0.isEmpty }.joined(separator: ", ") })
        switch target {
        case .nearbyToken(let token): body.toToken = token
        case .user(let userID): body.toUserID = userID
        case .slug(let slug): body.toSlug = slug
        }
        let request = try await api.connect.sendRequest(body)
        var applier = SyncApplier(context: context, mode: .pull)
        applier.apply(request)
        try? context.save()
        return request
    }

    /// Waits for the peer: accepted (connection saved) / no response (expired, declined or the
    /// deadline `expiresAt` + 2 s passed) / cancelled.
    public func outcome(of request: ConnectRequestDTO) async -> ConnectOutcome {
        let (stream, continuation) = AsyncStream.makeStream(of: ConnectEvent.self, bufferingPolicy: .bufferingNewest(32))
        let subscriberID = UUID()
        subscribers[subscriberID] = continuation
        let deadline = request.expiresAt ?? .now.addingTimeInterval(60)
        let timer = Task {
            try? await Task.sleep(for: .seconds(max(0, deadline.timeIntervalSinceNow) + 2))
            continuation.finish()
        }
        defer {
            timer.cancel()
            subscribers[subscriberID] = nil
            continuation.finish()
        }
        // Ends on the deadline (timer finishes the stream) or when the waiting task is cancelled.
        for await event in stream {
            guard case .requestUpdated(let updated, let connection) = event, updated.id == request.id else { continue }
            if let outcome = outcome(for: updated, connection: connection) { return outcome }
        }
        if Task.isCancelled { return .cancelled }
        // Realtime may have been down: ask once, and keep the answer.
        guard let latest = try? await api.connect.fetchRequest(id: request.id) else { return .noResponse }
        var applier = SyncApplier(context: container.mainContext, mode: .pull)
        applier.apply(latest)
        try? container.mainContext.save()
        return outcome(for: latest, connection: nil) ?? .noResponse
    }

    private func outcome(for request: ConnectRequestDTO, connection: ConnectionDTO?) -> ConnectOutcome? {
        switch request.status {
        case .pending:
            return nil
        case .accepted:
            if let connection { return .accepted(connectionID: connection.id) }
            let peer = request.peer.userID
            let local = try? container.mainContext.fetch(FetchDescriptor<Connection>(predicate: #Predicate { $0.remoteUserID == peer })).first
            if let local { return .accepted(connectionID: local.id) }
            onSyncHint()
            return nil
        case .declined, .expired:
            return .noResponse
        case .cancelled:
            return .cancelled
        }
    }

    public func cancel(_ request: ConnectRequestDTO) async {
        guard let updated = try? await api.connect.cancelRequest(id: request.id) else { return }
        var applier = SyncApplier(context: container.mainContext, mode: .pull)
        applier.apply(updated)
        try? container.mainContext.save()
    }

    /// Accepts an incoming request and returns the new connection (route to CONNECTED).
    /// Offline: the accept is queued (status set locally, pushed by sync) and nil is returned.
    @discardableResult
    public func accept(_ request: ConnectRequest, sharing cardID: UUID) async throws -> Connection? {
        let context = container.mainContext
        do {
            let response = try await api.connect.acceptRequest(id: request.id, AcceptConnectRequest(cardID: cardID))
            context.upsert(response.request)
            let connection = context.upsert(response.connection)
            try? context.save()
            return connection
        } catch APIError.offline {
            request.status = .accepted
            request.myCardID = cardID
            request.markChanged()
            try? context.save()
            return nil
        }
    }

    /// Declines quietly (the requester only ever sees "No response"). Queued when offline.
    public func decline(_ request: ConnectRequest) async throws {
        let context = container.mainContext
        do {
            context.upsert(try await api.connect.declineRequest(id: request.id))
        } catch APIError.offline {
            request.status = .declined
            request.markChanged()
        }
        try? context.save()
    }

    /// Pulls pending incoming requests now (People "Requests" pull-to-refresh).
    public func refreshIncomingRequests() async throws {
        let requests = try await api.connect.listRequests(status: .pending, direction: .incoming)
        var applier = SyncApplier(context: container.mainContext, mode: .pull)
        for request in requests { applier.apply(request) }
        try? container.mainContext.save()
    }

    /// DEFERRED_WELCOME "Connect": a deferred request is pre-approved, so both sides are
    /// connected right away; the connection arrives via realtime / the next sync.
    public func connect(with invite: DeferredInvite, sharing cardID: UUID) async throws {
        _ = try await sendConnectRequest(to: .slug(invite.cardSlug), cardID: cardID, method: .deferred)
        onSyncHint()
    }

    // MARK: Previews

    /// Mock-backed client for `#Preview`s (seeded with the demo account, ~300 ms latency).
    public static func preview(container: ModelContainer, online: Bool = true) -> MetlyClient {
        let server = MockMetlyServer(seed: .demo, isReachable: online)
        return MetlyClient(api: server, container: container, mockServer: server)
    }
}
