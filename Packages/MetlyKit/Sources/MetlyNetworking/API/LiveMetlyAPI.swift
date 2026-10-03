import Foundation
import MetlyCore

/// The real backend over HTTPS (+ WebSocket for realtime).
public struct LiveMetlyAPI: MetlyAPI {
    public let client: APIClient
    private let realtimeConnection: LiveRealtimeConnection

    public init(client: APIClient, urlSession: URLSession = APIClient.makeURLSession()) {
        self.client = client
        realtimeConnection = LiveRealtimeConnection(client: client, urlSession: urlSession)
    }

    public var auth: any AuthAPI { self }
    public var account: any AccountAPI { self }
    public var profile: any ProfileAPI { self }
    public var cards: any CardsAPI { self }
    public var wallet: any WalletAPI { self }
    public var connections: any ConnectionsAPI { self }
    public var blocks: any BlocksAPI { self }
    public var followUps: any FollowUpsAPI { self }
    public var events: any EventsAPI { self }
    public var connect: any ConnectAPI { self }
    public var realtime: any RealtimeAPI { realtimeConnection }
    public var publicProfiles: any PublicProfilesAPI { self }
    public var deferredLinks: any DeferredLinksAPI { self }
    public var subscriptions: any SubscriptionsAPI { self }
    public var devices: any DevicesAPI { self }
    public var sync: any SyncAPI { self }

    private func send<R: Decodable & Sendable>(_ method: HTTPMethod, _ path: String, query: [URLQueryItem] = [],
                                                auth: Bool = true, idempotent: Bool = false) async throws -> R {
        try await client.send(Endpoint<R>(method, path, query: query, requiresAuth: auth,
                                          idempotencyKey: idempotent ? UUID().uuidString : nil))
    }

    private func send<R: Decodable & Sendable>(_ method: HTTPMethod, _ path: String, body: some Encodable,
                                                query: [URLQueryItem] = [], auth: Bool = true,
                                                idempotent: Bool = false) async throws -> R {
        try await client.send(Endpoint<R>(method, path, body: body, query: query, requiresAuth: auth,
                                          idempotencyKey: idempotent ? UUID().uuidString : nil))
    }

    private func id(_ uuid: UUID) -> String { uuid.uuidString.lowercased() }
}

extension LiveMetlyAPI: AuthAPI {
    public func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse {
        try await send(.post, "/v1/auth/apple", body: request, auth: false, idempotent: true)
    }

    public func signInWithGoogle(_ request: GoogleSignInRequest) async throws -> AuthResponse {
        try await send(.post, "/v1/auth/google", body: request, auth: false, idempotent: true)
    }

    public func logout(_ request: LogoutRequest) async throws {
        let _: EmptyResponse = try await send(.post, "/v1/auth/logout", body: request, auth: true, idempotent: true)
    }
}

extension LiveMetlyAPI: AccountAPI {
    public func fetchMe() async throws -> MeResponse { try await send(.get, "/v1/me") }

    public func deleteAccount() async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/me")
    }

    public func requestDataExport() async throws -> DataExportResponse {
        try await send(.post, "/v1/me/export", idempotent: true)
    }
}

extension LiveMetlyAPI: ProfileAPI {
    public func fetchProfile() async throws -> ProfileDTO { try await send(.get, "/v1/me/profile") }

    public func updateProfile(_ profile: ProfileDTO) async throws -> ProfileDTO {
        try await send(.put, "/v1/me/profile", body: profile)
    }

    public func fetchSettings() async throws -> SettingsDTO { try await send(.get, "/v1/me/settings") }

    public func updateSettings(_ patch: SettingsPatch) async throws -> SettingsDTO {
        try await send(.patch, "/v1/me/settings", body: patch, idempotent: true)
    }

    public func requestImageUpload(_ kind: ProfileImageKind, _ request: UploadTicketRequest) async throws -> UploadTicket {
        try await send(.post, "/v1/me/profile/\(kind.rawValue)/upload", body: request, idempotent: true)
    }

    public func upload(_ data: Data, using ticket: UploadTicket) async throws {
        guard data.count <= ticket.maxBytes else {
            throw APIError.server(status: 413, problem: APIProblem(.payloadTooLarge, "Image is larger than \(ticket.maxBytes) bytes."))
        }
        let endpoint = Endpoint<EmptyResponse>(method: HTTPMethod(rawValue: ticket.method) ?? .put, path: "", body: data,
                                               headers: ticket.headers, requiresAuth: false,
                                               absoluteURL: ticket.uploadURL, timeout: 120) { _, _ in EmptyResponse() }
        _ = try await client.send(endpoint)
    }

    public func commitImageUpload(_ kind: ProfileImageKind, uploadID: String) async throws -> ProfileDTO {
        try await send(.put, "/v1/me/profile/\(kind.rawValue)", body: CommitUploadRequest(uploadID: uploadID))
    }

    public func deleteImage(_ kind: ProfileImageKind) async throws -> ProfileDTO {
        try await send(.delete, "/v1/me/profile/\(kind.rawValue)")
    }

    public func downloadAsset(_ url: URL) async throws -> Data {
        try await client.send(.raw(absoluteURL: url, accept: "image/*", requiresAuth: false))
    }

    public func requestTelegramLink() async throws -> TelegramLinkDTO {
        try await send(.post, "/v1/integrations/telegram/link", idempotent: true)
    }

    public func unlinkTelegram() async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/integrations/telegram/link")
    }
}

extension LiveMetlyAPI: CardsAPI {
    public func listCards() async throws -> [CardDTO] {
        let page: Page<CardDTO> = try await send(.get, "/v1/cards")
        return page.items
    }

    public func fetchCard(id cardID: UUID) async throws -> CardDTO { try await send(.get, "/v1/cards/\(id(cardID))") }

    public func upsertCard(_ card: CardDTO) async throws -> CardDTO {
        try await send(.put, "/v1/cards/\(id(card.id))", body: card)
    }

    public func publishCard(_ card: CardDTO) async throws -> CardDTO {
        try await send(.post, "/v1/cards/\(id(card.id))/publish", body: card, idempotent: true)
    }

    public func deleteCard(id cardID: UUID) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/cards/\(id(cardID))")
    }

    public func duplicateCard(id cardID: UUID, _ request: DuplicateCardRequest) async throws -> CardDTO {
        try await send(.post, "/v1/cards/\(id(cardID))/duplicate", body: request, idempotent: true)
    }

    public func reorderCards(_ request: ReorderCardsRequest) async throws -> [CardDTO] {
        let page: Page<CardDTO> = try await send(.put, "/v1/cards/order", body: request)
        return page.items
    }

    public func cardStats(id cardID: UUID) async throws -> CardStatsDTO {
        try await send(.get, "/v1/cards/\(id(cardID))/stats")
    }
}

extension LiveMetlyAPI: WalletAPI {
    public func walletPass(cardID: UUID) async throws -> Data {
        try await client.send(.raw(.get, "/v1/cards/\(id(cardID))/wallet-pass", accept: "application/vnd.apple.pkpass"))
    }
}

extension LiveMetlyAPI: ConnectionsAPI {
    public func listConnections(updatedSince: Date?, cursor: String?, limit: Int) async throws -> Page<ConnectionDTO> {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let updatedSince { query.append(URLQueryItem(name: "updatedSince", value: MetlyJSON.string(from: updatedSince))) }
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(.get, "/v1/connections", query: query)
    }

    public func upsertConnection(_ connection: ConnectionDTO) async throws -> ConnectionDTO {
        try await send(.put, "/v1/connections/\(id(connection.id))", body: connection)
    }

    public func deleteConnection(id connectionID: UUID) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/connections/\(id(connectionID))")
    }

    public func blockConnection(id connectionID: UUID) async throws -> ConnectionDTO {
        try await send(.post, "/v1/connections/\(id(connectionID))/block", idempotent: true)
    }
}

extension LiveMetlyAPI: BlocksAPI {
    public func listBlocks() async throws -> [BlockDTO] {
        let page: Page<BlockDTO> = try await send(.get, "/v1/me/blocks")
        return page.items
    }

    public func block(_ request: BlockRequest) async throws -> BlockDTO {
        try await send(.post, "/v1/me/blocks", body: request, idempotent: true)
    }

    public func unblock(userID: UUID) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/me/blocks/\(id(userID))")
    }
}

extension LiveMetlyAPI: FollowUpsAPI {
    public func listFollowUps(cursor: String?, limit: Int) async throws -> Page<FollowUpDTO> {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await send(.get, "/v1/followups", query: query)
    }

    public func upsertFollowUp(_ followUp: FollowUpDTO) async throws -> FollowUpDTO {
        try await send(.put, "/v1/followups/\(id(followUp.id))", body: followUp)
    }

    public func deleteFollowUp(id followUpID: UUID) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/followups/\(id(followUpID))")
    }

    public func bulkUpsertFollowUps(_ followUps: [FollowUpDTO]) async throws -> [FollowUpDTO] {
        let page: Page<FollowUpDTO> = try await send(.post, "/v1/followups/bulk", body: Page(items: followUps, nextCursor: nil),
                                                     idempotent: true)
        return page.items
    }
}

extension LiveMetlyAPI: EventsAPI {
    public func listEvents() async throws -> [EventDTO] {
        let page: Page<EventDTO> = try await send(.get, "/v1/events")
        return page.items
    }

    public func upsertEvent(_ event: EventDTO) async throws -> EventDTO {
        try await send(.put, "/v1/events/\(id(event.id))", body: event)
    }

    public func deleteEvent(id eventID: UUID) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/events/\(id(eventID))")
    }

    public func endEvent(id eventID: UUID) async throws -> EventDTO {
        try await send(.post, "/v1/events/\(id(eventID))/end", idempotent: true)
    }

    public func resumeEvent(id eventID: UUID) async throws -> EventDTO {
        try await send(.post, "/v1/events/\(id(eventID))/resume", idempotent: true)
    }

    public func eventSummary(id eventID: UUID) async throws -> EventSummaryDTO {
        try await send(.get, "/v1/events/\(id(eventID))/summary")
    }
}

extension LiveMetlyAPI: ConnectAPI {
    public func startSession(_ request: ConnectSessionRequest) async throws -> ConnectSessionDTO {
        try await send(.post, "/v1/connect/sessions", body: request, idempotent: true)
    }

    public func endSession(id sessionID: String) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/connect/sessions/\(sessionID)")
    }

    public func resolvePeers(tokens: [String]) async throws -> [NearbyPeerDTO] {
        guard !tokens.isEmpty else { return [] }
        let page: Page<NearbyPeerDTO> = try await send(.get, "/v1/connect/peers",
                                                       query: [URLQueryItem(name: "tokens", value: tokens.joined(separator: ","))])
        return page.items
    }

    public func sendRequest(_ request: SendConnectRequest) async throws -> ConnectRequestDTO {
        try await send(.post, "/v1/connect/requests", body: request, idempotent: true)
    }

    public func listRequests(status: ConnectRequestStatus?, direction: ConnectRequestDirection?) async throws -> [ConnectRequestDTO] {
        var query: [URLQueryItem] = []
        if let status { query.append(URLQueryItem(name: "status", value: status.rawValue)) }
        if let direction { query.append(URLQueryItem(name: "direction", value: direction.rawValue)) }
        let page: Page<ConnectRequestDTO> = try await send(.get, "/v1/connect/requests", query: query)
        return page.items
    }

    public func fetchRequest(id requestID: UUID) async throws -> ConnectRequestDTO {
        try await send(.get, "/v1/connect/requests/\(id(requestID))")
    }

    public func acceptRequest(id requestID: UUID, _ request: AcceptConnectRequest) async throws -> ConnectAcceptResponse {
        try await send(.post, "/v1/connect/requests/\(id(requestID))/accept", body: request, idempotent: true)
    }

    public func declineRequest(id requestID: UUID) async throws -> ConnectRequestDTO {
        try await send(.post, "/v1/connect/requests/\(id(requestID))/decline", idempotent: true)
    }

    public func cancelRequest(id requestID: UUID) async throws -> ConnectRequestDTO {
        try await send(.post, "/v1/connect/requests/\(id(requestID))/cancel", idempotent: true)
    }
}

extension LiveMetlyAPI: PublicProfilesAPI {
    public func publicProfile(slug: String) async throws -> PublicCardDTO {
        // `URL.appending(path:)` percent-encodes; slugs are `[a-z0-9-]` anyway.
        try await send(.get, "/v1/public-profiles/\(slug.lowercased())")
    }
}

extension LiveMetlyAPI: DeferredLinksAPI {
    public func claim(_ request: DeferredLinkClaimRequest) async throws -> DeferredInviteDTO? {
        let response: DeferredLinkClaimResponse = try await send(.post, "/v1/deferred-links/claim", body: request,
                                                                 auth: false, idempotent: true)
        return response.invite
    }
}

extension LiveMetlyAPI: SubscriptionsAPI {
    public func verify(_ request: VerifyTransactionRequest) async throws -> EntitlementDTO {
        try await send(.post, "/v1/subscriptions/verify", body: request, idempotent: true)
    }

    public func fetchEntitlement() async throws -> EntitlementDTO { try await send(.get, "/v1/me/entitlements") }
}

extension LiveMetlyAPI: DevicesAPI {
    public func registerDevice(_ request: DeviceRegistrationRequest) async throws {
        let _: EmptyResponse = try await send(.put, "/v1/me/devices/\(request.deviceID)", body: request)
    }

    public func unregisterDevice(id deviceID: String) async throws {
        let _: EmptyResponse = try await send(.delete, "/v1/me/devices/\(deviceID)")
    }
}

extension LiveMetlyAPI: SyncAPI {
    public func push(_ request: SyncPushRequest) async throws -> SyncPushResponse {
        try await send(.post, "/v1/sync/push", body: request, idempotent: true)
    }

    public func pull(since cursor: String?, limit: Int) async throws -> SyncPullResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor { query.append(URLQueryItem(name: "since", value: cursor)) }
        return try await send(.get, "/v1/sync", query: query)
    }
}
