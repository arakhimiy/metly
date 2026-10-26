import Foundation
import MetlyCore

// Endpoint groups of the Tanishly backend (docs/api/openapi.yaml). Implemented by `LiveMetlyAPI`
// (URLSession) and `MockMetlyServer` (in-memory). Every method throws `APIError`.

public protocol AuthAPI: Sendable {
    /// `POST /v1/auth/apple`
    func signInWithApple(_ request: AppleSignInRequest) async throws -> AuthResponse
    /// `POST /v1/auth/google`
    func signInWithGoogle(_ request: GoogleSignInRequest) async throws -> AuthResponse
    /// `POST /v1/auth/logout` — revokes the refresh token (best effort; local sign-out never waits on it).
    func logout(_ request: LogoutRequest) async throws
    #if DEBUG
    /// `POST /v1/auth/dev` — only a local backend with `DEV_AUTH_ENABLED` answers it.
    func signInForDevelopment(_ request: DevSignInRequest) async throws -> AuthResponse
    #endif
}

#if DEBUG
extension AuthAPI {
    public func signInForDevelopment(_ request: DevSignInRequest) async throws -> AuthResponse {
        throw APIError.serverRequired("Test sign-in needs a local Tanishly backend.")
    }
}
#endif

public protocol AccountAPI: Sendable {
    /// `GET /v1/me`
    func fetchMe() async throws -> MeResponse
    /// `DELETE /v1/me` — irreversible; cards/links stop working, other users keep what you shared.
    func deleteAccount() async throws
    /// `POST /v1/me/export` — emails a download link.
    func requestDataExport() async throws -> DataExportResponse
}

public protocol ProfileAPI: Sendable {
    /// `GET /v1/me/profile`
    func fetchProfile() async throws -> ProfileDTO
    /// `PUT /v1/me/profile` (LWW on `updatedAt`).
    func updateProfile(_ profile: ProfileDTO) async throws -> ProfileDTO
    /// `GET /v1/me/settings`
    func fetchSettings() async throws -> SettingsDTO
    /// `PATCH /v1/me/settings`
    func updateSettings(_ patch: SettingsPatch) async throws -> SettingsDTO
    /// `POST /v1/me/profile/{kind}/upload` → presigned PUT.
    func requestImageUpload(_ kind: ProfileImageKind, _ request: UploadTicketRequest) async throws -> UploadTicket
    /// PUT the bytes to the presigned URL (no API auth).
    func upload(_ data: Data, using ticket: UploadTicket) async throws
    /// `PUT /v1/me/profile/{kind}` — attach the uploaded object.
    func commitImageUpload(_ kind: ProfileImageKind, uploadID: String) async throws -> ProfileDTO
    /// `DELETE /v1/me/profile/{kind}`
    func deleteImage(_ kind: ProfileImageKind) async throws -> ProfileDTO
    /// GET an asset URL returned by the API (photos/logos/avatars).
    func downloadAsset(_ url: URL) async throws -> Data
    /// `POST /v1/integrations/telegram/link` — reminder delivery via @TanishlyBot.
    func requestTelegramLink() async throws -> TelegramLinkDTO
    /// `DELETE /v1/integrations/telegram/link`
    func unlinkTelegram() async throws
}

public protocol CardsAPI: Sendable {
    /// `GET /v1/cards`
    func listCards() async throws -> [CardDTO]
    /// `GET /v1/cards/{id}`
    func fetchCard(id: UUID) async throws -> CardDTO
    /// `PUT /v1/cards/{id}` — create-or-update by client id; publishes and assigns a slug.
    func upsertCard(_ card: CardDTO) async throws -> CardDTO
    /// `POST /v1/cards/{id}/publish` — upsert + publish now (CARD_CREATE "Publish", Editor "Done").
    func publishCard(_ card: CardDTO) async throws -> CardDTO
    /// `DELETE /v1/cards/{id}` — link and QR stop working.
    func deleteCard(id: UUID) async throws
    /// `POST /v1/cards/{id}/duplicate` (Free limit enforced).
    func duplicateCard(id: UUID, _ request: DuplicateCardRequest) async throws -> CardDTO
    /// `PUT /v1/cards/order`
    func reorderCards(_ request: ReorderCardsRequest) async throws -> [CardDTO]
    /// `GET /v1/cards/{id}/stats`
    func cardStats(id: UUID) async throws -> CardStatsDTO
}

public protocol WalletAPI: Sendable {
    /// `GET /v1/cards/{id}/wallet-pass` → signed `.pkpass` bytes.
    func walletPass(cardID: UUID) async throws -> Data
}

public protocol ConnectionsAPI: Sendable {
    /// `GET /v1/connections?updatedSince=&cursor=&limit=`
    func listConnections(updatedSince: Date?, cursor: String?, limit: Int) async throws -> Page<ConnectionDTO>
    /// `PUT /v1/connections/{id}`
    func upsertConnection(_ connection: ConnectionDTO) async throws -> ConnectionDTO
    /// `DELETE /v1/connections/{id}` — one-sided remove.
    func deleteConnection(id: UUID) async throws
    /// `POST /v1/connections/{id}/block`
    func blockConnection(id: UUID) async throws -> ConnectionDTO
}

public protocol BlocksAPI: Sendable {
    /// `GET /v1/me/blocks`
    func listBlocks() async throws -> [BlockDTO]
    /// `POST /v1/me/blocks`
    func block(_ request: BlockRequest) async throws -> BlockDTO
    /// `DELETE /v1/me/blocks/{userId}`
    func unblock(userID: UUID) async throws
}

public protocol FollowUpsAPI: Sendable {
    /// `GET /v1/followups?cursor=&limit=`
    func listFollowUps(cursor: String?, limit: Int) async throws -> Page<FollowUpDTO>
    /// `PUT /v1/followups/{id}` (Free: max 5 open, enforced server-side).
    func upsertFollowUp(_ followUp: FollowUpDTO) async throws -> FollowUpDTO
    /// `DELETE /v1/followups/{id}`
    func deleteFollowUp(id: UUID) async throws
    /// `POST /v1/followups/bulk` ("Follow up with everyone I haven't yet").
    func bulkUpsertFollowUps(_ followUps: [FollowUpDTO]) async throws -> [FollowUpDTO]
}

public protocol EventsAPI: Sendable {
    /// `GET /v1/events`
    func listEvents() async throws -> [EventDTO]
    /// `PUT /v1/events/{id}` (Free: max 1 active; rename cascades to tagged connections).
    func upsertEvent(_ event: EventDTO) async throws -> EventDTO
    /// `DELETE /v1/events/{id}`
    func deleteEvent(id: UUID) async throws
    /// `POST /v1/events/{id}/end`
    func endEvent(id: UUID) async throws -> EventDTO
    /// `POST /v1/events/{id}/resume`
    func resumeEvent(id: UUID) async throws -> EventDTO
    /// `GET /v1/events/{id}/summary`
    func eventSummary(id: UUID) async throws -> EventSummaryDTO
}

public protocol ConnectAPI: Sendable {
    /// `POST /v1/connect/sessions`
    func startSession(_ request: ConnectSessionRequest) async throws -> ConnectSessionDTO
    /// `DELETE /v1/connect/sessions/{id}`
    func endSession(id: String) async throws
    /// `GET /v1/connect/peers?tokens=`
    func resolvePeers(tokens: [String]) async throws -> [NearbyPeerDTO]
    /// `POST /v1/connect/requests`
    func sendRequest(_ request: SendConnectRequest) async throws -> ConnectRequestDTO
    /// `GET /v1/connect/requests?status=&direction=`
    func listRequests(status: ConnectRequestStatus?, direction: ConnectRequestDirection?) async throws -> [ConnectRequestDTO]
    /// `GET /v1/connect/requests/{id}`
    func fetchRequest(id: UUID) async throws -> ConnectRequestDTO
    /// `POST /v1/connect/requests/{id}/accept`
    func acceptRequest(id: UUID, _ request: AcceptConnectRequest) async throws -> ConnectAcceptResponse
    /// `POST /v1/connect/requests/{id}/decline` — the requester is never told.
    func declineRequest(id: UUID) async throws -> ConnectRequestDTO
    /// `POST /v1/connect/requests/{id}/cancel`
    func cancelRequest(id: UUID) async throws -> ConnectRequestDTO
}

public protocol RealtimeAPI: Sendable {
    /// Live events (`GET /v1/realtime` WebSocket). Each call returns an independent stream;
    /// the connection stays open while at least one stream is being iterated.
    func connectEvents() async -> AsyncStream<ConnectEvent>
}

public protocol PublicProfilesAPI: Sendable {
    /// `GET /v1/public-profiles/{slug}` — scanned Tanishly QR, as visible to the signed-in viewer.
    func publicProfile(slug: String) async throws -> PublicCardDTO
}

public protocol DeferredLinksAPI: Sendable {
    /// `POST /v1/deferred-links/claim` — nil when nothing matched.
    func claim(_ request: DeferredLinkClaimRequest) async throws -> DeferredInviteDTO?
}

public protocol SubscriptionsAPI: Sendable {
    /// `POST /v1/subscriptions/verify`
    func verify(_ request: VerifyTransactionRequest) async throws -> EntitlementDTO
    /// `GET /v1/me/entitlements`
    func fetchEntitlement() async throws -> EntitlementDTO
}

public protocol DevicesAPI: Sendable {
    /// `PUT /v1/me/devices/{deviceId}`
    func registerDevice(_ request: DeviceRegistrationRequest) async throws
    /// `DELETE /v1/me/devices/{deviceId}`
    func unregisterDevice(id: String) async throws
}

public protocol SyncAPI: Sendable {
    /// `POST /v1/sync/push`
    func push(_ request: SyncPushRequest) async throws -> SyncPushResponse
    /// `GET /v1/sync?since=&limit=` — `since == nil` is a full snapshot.
    func pull(since cursor: String?, limit: Int) async throws -> SyncPullResponse
}

/// The whole backend, grouped by area: `api.cards.publishCard(dto)`, `api.connect.sendRequest(…)`.
public protocol MetlyAPI: Sendable {
    var auth: any AuthAPI { get }
    var account: any AccountAPI { get }
    var profile: any ProfileAPI { get }
    var cards: any CardsAPI { get }
    var wallet: any WalletAPI { get }
    var connections: any ConnectionsAPI { get }
    var blocks: any BlocksAPI { get }
    var followUps: any FollowUpsAPI { get }
    var events: any EventsAPI { get }
    var connect: any ConnectAPI { get }
    var realtime: any RealtimeAPI { get }
    var publicProfiles: any PublicProfilesAPI { get }
    var deferredLinks: any DeferredLinksAPI { get }
    var subscriptions: any SubscriptionsAPI { get }
    var devices: any DevicesAPI { get }
    var sync: any SyncAPI { get }
}
