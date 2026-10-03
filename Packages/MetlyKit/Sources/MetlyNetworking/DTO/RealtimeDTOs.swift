import Foundation

public enum RealtimeState: String, Sendable, Hashable { case disconnected, connecting, connected }

/// Everything the realtime channel (`wss://…/v1/realtime`) delivers, already decoded.
/// Realtime is best-effort: anything missed is also reachable via `/v1/sync` and
/// `GET /v1/connect/requests`, which clients call after every reconnect.
public enum ConnectEvent: Sendable, Hashable {
    /// Someone wants to connect (INCOMING_REQUEST / People "Requests").
    case requestReceived(ConnectRequestDTO)
    /// A request changed status. For accepted requests `connection` is the caller's new connection.
    case requestUpdated(ConnectRequestDTO, connection: ConnectionDTO?)
    /// A web visitor shared their contact back (connection already created/merged server-side).
    case shareBackReceived(ShareBackNoticeDTO)
    /// Server-side data changed (another device, server merge) — run a sync pull.
    case syncAvailable
    /// Transport state of the realtime connection (never sent by the server).
    case stateChanged(RealtimeState)
}

/// Wire envelope: `{ "type": "connect.request.updated", "id": "evt_…", "sentAt": "…", "data": { … } }`.
public struct RealtimeMessage: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case connectRequestReceived = "connect.request.received"
        case connectRequestUpdated = "connect.request.updated"
        case shareBackReceived = "shareback.received"
        case syncAvailable = "sync.available"
        case ping
        case pong
    }

    public var type: String
    public var id: String?
    public var sentAt: Date?
    /// nil for `ping`/`pong` and unknown types (ignore them — forward compatibility).
    public var event: ConnectEvent?

    private struct RequestUpdatedData: Codable {
        var request: ConnectRequestDTO
        var connection: ConnectionDTO?
    }

    private struct SyncAvailableData: Codable {
        var cursor: String?
    }

    private enum CodingKeys: String, CodingKey { case type, id, sentAt, data }

    public init(type: Kind, id: String? = nil, sentAt: Date? = nil, event: ConnectEvent? = nil) {
        self.type = type.rawValue
        self.id = id
        self.sentAt = sentAt
        self.event = event
    }

    public init(event: ConnectEvent, id: String = "evt_\(UUID().uuidString.lowercased())", sentAt: Date = .now) {
        let kind: Kind = switch event {
        case .requestReceived: .connectRequestReceived
        case .requestUpdated: .connectRequestUpdated
        case .shareBackReceived: .shareBackReceived
        case .syncAvailable, .stateChanged: .syncAvailable
        }
        self.init(type: kind, id: id, sentAt: sentAt, event: event)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        sentAt = try container.decodeIfPresent(Date.self, forKey: .sentAt)
        switch Kind(rawValue: type) {
        case .connectRequestReceived:
            event = .requestReceived(try container.decode(ConnectRequestDTO.self, forKey: .data))
        case .connectRequestUpdated:
            let data = try container.decode(RequestUpdatedData.self, forKey: .data)
            event = .requestUpdated(data.request, connection: data.connection)
        case .shareBackReceived:
            event = .shareBackReceived(try container.decode(ShareBackNoticeDTO.self, forKey: .data))
        case .syncAvailable:
            event = .syncAvailable
        case .ping, .pong, nil:
            event = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(sentAt, forKey: .sentAt)
        switch event {
        case .requestReceived(let request):
            try container.encode(request, forKey: .data)
        case .requestUpdated(let request, let connection):
            try container.encode(RequestUpdatedData(request: request, connection: connection), forKey: .data)
        case .shareBackReceived(let notice):
            try container.encode(notice, forKey: .data)
        case .syncAvailable:
            try container.encode(SyncAvailableData(cursor: nil), forKey: .data)
        case .stateChanged, nil:
            break
        }
    }
}
