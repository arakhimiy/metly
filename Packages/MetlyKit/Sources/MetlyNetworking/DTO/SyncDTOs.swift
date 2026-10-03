import Foundation
import MetlyCore

/// A set of record changes grouped by type. Used in both directions:
/// push body (`connectRequests` ignored), push canonical echo, and pull deltas.
public struct SyncChanges: Codable, Sendable, Hashable {
    public var profile: ProfileDTO?
    public var cards: [CardDTO]
    public var events: [EventDTO]
    public var connections: [ConnectionDTO]
    public var followUps: [FollowUpDTO]
    public var connectRequests: [ConnectRequestDTO]
    public var tombstones: [TombstoneDTO]

    public init(profile: ProfileDTO? = nil, cards: [CardDTO] = [], events: [EventDTO] = [], connections: [ConnectionDTO] = [],
                followUps: [FollowUpDTO] = [], connectRequests: [ConnectRequestDTO] = [], tombstones: [TombstoneDTO] = []) {
        self.profile = profile
        self.cards = cards
        self.events = events
        self.connections = connections
        self.followUps = followUps
        self.connectRequests = connectRequests
        self.tombstones = tombstones
    }

    /// Omitted arrays decode as empty.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile = try container.decodeIfPresent(ProfileDTO.self, forKey: .profile)
        cards = try container.decodeIfPresent([CardDTO].self, forKey: .cards) ?? []
        events = try container.decodeIfPresent([EventDTO].self, forKey: .events) ?? []
        connections = try container.decodeIfPresent([ConnectionDTO].self, forKey: .connections) ?? []
        followUps = try container.decodeIfPresent([FollowUpDTO].self, forKey: .followUps) ?? []
        connectRequests = try container.decodeIfPresent([ConnectRequestDTO].self, forKey: .connectRequests) ?? []
        tombstones = try container.decodeIfPresent([TombstoneDTO].self, forKey: .tombstones) ?? []
    }

    public var isEmpty: Bool {
        profile == nil && cards.isEmpty && events.isEmpty && connections.isEmpty && followUps.isEmpty
            && connectRequests.isEmpty && tombstones.isEmpty
    }

    public var count: Int {
        (profile == nil ? 0 : 1) + cards.count + events.count + connections.count + followUps.count
            + connectRequests.count + tombstones.count
    }
}

/// `POST /v1/sync/push`.
public struct SyncPushRequest: Codable, Sendable, Hashable {
    public var deviceID: String?
    public var changes: SyncChanges

    public init(deviceID: String?, changes: SyncChanges) {
        self.deviceID = deviceID
        self.changes = changes
    }
}

public enum SyncResultStatus: String, Codable, Sendable {
    /// The change was stored. The canonical record (with server-owned fields) is in `records`.
    case applied
    /// The server holds a newer version (`updatedAt` wins). Canonical record/tombstone is in `records`.
    case stale
    /// Validation or plan-limit failure (`error` explains). Nothing was stored.
    case rejected
}

public struct SyncResultDTO: Codable, Sendable, Hashable {
    public var type: SyncRecordType
    public var id: UUID
    public var status: SyncResultStatus
    public var error: APIProblem?

    public init(type: SyncRecordType, id: UUID, status: SyncResultStatus, error: APIProblem? = nil) {
        self.type = type
        self.id = id
        self.status = status
        self.error = error
    }
}

public struct SyncPushResponse: Codable, Sendable, Hashable {
    /// One result per pushed record/tombstone, in request order.
    public var results: [SyncResultDTO]
    /// Canonical server state for every applied or stale change.
    public var records: SyncChanges
    public var serverTime: Date

    public init(results: [SyncResultDTO], records: SyncChanges, serverTime: Date) {
        self.results = results
        self.records = records
        self.serverTime = serverTime
    }
}

/// `GET /v1/sync?since={cursor}&limit={n}`.
public struct SyncPullResponse: Codable, Sendable, Hashable {
    public var changes: SyncChanges
    /// Opaque; pass back as `since`. Store it only after the page was applied.
    public var cursor: String
    public var hasMore: Bool
    public var serverTime: Date
    /// Included on the first page.
    public var entitlement: EntitlementDTO?

    public init(changes: SyncChanges, cursor: String, hasMore: Bool, serverTime: Date, entitlement: EntitlementDTO? = nil) {
        self.changes = changes
        self.cursor = cursor
        self.hasMore = hasMore
        self.serverTime = serverTime
        self.entitlement = entitlement
    }
}
