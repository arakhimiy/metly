import Foundation
import MetlyCore

// Synced records — one DTO per SwiftData model. The same shape is used by REST endpoints,
// `POST /v1/sync/push` and `GET /v1/sync`. Fields marked "server-owned" are ignored on write.
// Every record carries `updatedAt` (client-authored, last-write-wins) and `deletedAt` (tombstone).

/// Common sync bookkeeping, used by the generic sync code.
public protocol SyncRecordDTO: Codable, Sendable, Hashable, Identifiable where ID == UUID {
    static var recordType: SyncRecordType { get }
    var id: UUID { get }
    var updatedAt: Date { get }
    var deletedAt: Date? { get }
}

public enum SyncRecordType: String, Codable, Sendable, CaseIterable {
    case profile, card, event, connection, followUp, connectRequest
}

// MARK: Profile (+ synced settings)

public struct ProfileDTO: SyncRecordDTO {
    public static let recordType = SyncRecordType.profile
    public var id: UUID
    public var fullName: String
    public var jobTitle: String
    public var company: String
    /// Server-owned. Set via the photo upload flow.
    public var photoURL: URL?
    /// Server-owned. Set via the logo upload flow.
    public var logoURL: URL?
    public var contactFields: [ContactField]
    public var defaultCardID: UUID?
    public var linksPaused: Bool
    public var notificationPrefs: NotificationPrefs
    public var privacySettings: PrivacySettings
    public var isSetupComplete: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, fullName: String, jobTitle: String, company: String, photoURL: URL? = nil, logoURL: URL? = nil,
                contactFields: [ContactField], defaultCardID: UUID?, linksPaused: Bool, notificationPrefs: NotificationPrefs,
                privacySettings: PrivacySettings, isSetupComplete: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.photoURL = photoURL
        self.logoURL = logoURL
        self.contactFields = contactFields
        self.defaultCardID = defaultCardID
        self.linksPaused = linksPaused
        self.notificationPrefs = notificationPrefs
        self.privacySettings = privacySettings
        self.isSetupComplete = isSetupComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// `GET/PATCH /v1/me/settings` — the settings subset of the profile.
public struct SettingsDTO: Codable, Sendable, Hashable {
    public var notificationPrefs: NotificationPrefs
    public var privacySettings: PrivacySettings
    public var linksPaused: Bool
    public var defaultCardID: UUID?
    public var updatedAt: Date

    public init(notificationPrefs: NotificationPrefs, privacySettings: PrivacySettings, linksPaused: Bool,
                defaultCardID: UUID?, updatedAt: Date) {
        self.notificationPrefs = notificationPrefs
        self.privacySettings = privacySettings
        self.linksPaused = linksPaused
        self.defaultCardID = defaultCardID
        self.updatedAt = updatedAt
    }
}

/// Partial update — only non-nil members change. `updatedAt` is the client edit time (LWW).
public struct SettingsPatch: Codable, Sendable, Hashable {
    public var notificationPrefs: NotificationPrefs?
    public var privacySettings: PrivacySettings?
    public var linksPaused: Bool?
    public var defaultCardID: UUID?
    public var updatedAt: Date

    public init(notificationPrefs: NotificationPrefs? = nil, privacySettings: PrivacySettings? = nil,
                linksPaused: Bool? = nil, defaultCardID: UUID? = nil, updatedAt: Date = .now) {
        self.notificationPrefs = notificationPrefs
        self.privacySettings = privacySettings
        self.linksPaused = linksPaused
        self.defaultCardID = defaultCardID
        self.updatedAt = updatedAt
    }
}

// MARK: Card

public struct CardDTO: SyncRecordDTO {
    public static let recordType = SyncRecordType.card
    public var id: UUID
    public var name: String
    /// Server-owned: `{firstname}-{4 chars}`, assigned on first publish, immutable in v1.
    public var slug: String?
    /// Server-owned: `https://tanishly.app/c/{slug}`.
    public var url: URL?
    public var sortOrder: Int
    public var design: CardDesign
    /// Server-owned: `published` once the server accepted the card (there are no server-side drafts).
    public var publishState: CardPublishState
    /// Server-owned: true for cards beyond the Free limit after a Pro downgrade.
    public var isReadOnly: Bool
    /// Server-owned: true while the owner's links are paused (mirrors `ProfileDTO.linksPaused` in v1).
    public var isPaused: Bool
    /// Server-owned, may lag a few minutes.
    public var stats: CardStats?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, name: String, slug: String? = nil, url: URL? = nil, sortOrder: Int, design: CardDesign,
                publishState: CardPublishState = .draft, isReadOnly: Bool = false, isPaused: Bool = false,
                stats: CardStats? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.url = url
        self.sortOrder = sortOrder
        self.design = design
        self.publishState = publishState
        self.isReadOnly = isReadOnly
        self.isPaused = isPaused
        self.stats = stats
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: Event

public struct EventDTO: SyncRecordDTO {
    public static let recordType = SyncRecordType.event
    public var id: UUID
    public var name: String
    public var place: String
    public var city: String
    public var startDate: Date
    public var endDate: Date
    public var cardID: UUID?
    public var status: EventStatus
    public var calendarEventIdentifier: String?
    public var endedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, name: String, place: String, city: String, startDate: Date, endDate: Date, cardID: UUID?,
                status: EventStatus, calendarEventIdentifier: String? = nil, endedAt: Date? = nil,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.place = place
        self.city = city
        self.startDate = startDate
        self.endDate = endDate
        self.cardID = cardID
        self.status = status
        self.calendarEventIdentifier = calendarEventIdentifier
        self.endedAt = endedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: Connection

public struct ConnectionDTO: SyncRecordDTO {
    public static let recordType = SyncRecordType.connection
    public var id: UUID
    public var remoteUserID: UUID?
    public var fullName: String
    public var jobTitle: String
    public var company: String
    public var phone: String
    public var email: String
    public var telegram: String
    public var website: String
    public var linkedin: String
    /// Server-owned (peer's profile photo for app users).
    public var avatarURL: URL?
    public var theirCard: CardSnapshot?
    public var mySharedCardID: UUID?
    public var source: ConnectionSource
    public var context: MeetingContext
    public var previousMeetings: [MeetingContext]
    public var eventID: UUID?
    public var note: String
    public var tags: [String]
    public var isMerged: Bool
    public var isPendingMerge: Bool
    public var isBlocked: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, remoteUserID: UUID? = nil, fullName: String, jobTitle: String = "", company: String = "",
                phone: String = "", email: String = "", telegram: String = "", website: String = "", linkedin: String = "",
                avatarURL: URL? = nil, theirCard: CardSnapshot? = nil, mySharedCardID: UUID? = nil, source: ConnectionSource,
                context: MeetingContext, previousMeetings: [MeetingContext] = [], eventID: UUID? = nil, note: String = "",
                tags: [String] = [], isMerged: Bool = false, isPendingMerge: Bool = false, isBlocked: Bool = false,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.remoteUserID = remoteUserID
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.phone = phone
        self.email = email
        self.telegram = telegram
        self.website = website
        self.linkedin = linkedin
        self.avatarURL = avatarURL
        self.theirCard = theirCard
        self.mySharedCardID = mySharedCardID
        self.source = source
        self.context = context
        self.previousMeetings = previousMeetings
        self.eventID = eventID
        self.note = note
        self.tags = tags
        self.isMerged = isMerged
        self.isPendingMerge = isPendingMerge
        self.isBlocked = isBlocked
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: FollowUp

public struct FollowUpDTO: SyncRecordDTO {
    public static let recordType = SyncRecordType.followUp
    public var id: UUID
    public var connectionID: UUID?
    public var title: String
    public var channel: FollowUpChannel
    public var dueAt: Date
    public var isDone: Bool
    public var completedAt: Date?
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, connectionID: UUID?, title: String, channel: FollowUpChannel, dueAt: Date, isDone: Bool = false,
                completedAt: Date? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.connectionID = connectionID
        self.title = title
        self.channel = channel
        self.dueAt = dueAt
        self.isDone = isDone
        self.completedAt = completedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

// MARK: ConnectRequest (server-driven; never pushed as a record — use the connect endpoints)

/// The other side of a connect request, as visible to the caller.
public struct PeerSummaryDTO: Codable, Sendable, Hashable {
    public var userID: UUID
    public var fullName: String
    public var jobTitle: String
    public var company: String
    public var avatarURL: URL?
    /// The card they offered (incoming) or returned (outgoing, after accept).
    public var card: CardSnapshot?

    public init(userID: UUID, fullName: String, jobTitle: String = "", company: String = "",
                avatarURL: URL? = nil, card: CardSnapshot? = nil) {
        self.userID = userID
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.avatarURL = avatarURL
        self.card = card
    }
}

public struct ConnectRequestDTO: SyncRecordDTO {
    public static let recordType = SyncRecordType.connectRequest
    public var id: UUID
    /// Relative to the caller.
    public var direction: ConnectRequestDirection
    public var peer: PeerSummaryDTO
    /// Caller's card offered (outgoing) or returned on accept (incoming).
    public var myCardID: UUID?
    public var method: ConnectMethod
    /// The requester sees `expired` (never `declined`) — SPEC §9 Q9.
    public var status: ConnectRequestStatus
    public var eventName: String?
    public var place: String?
    public var createdAt: Date
    public var respondedAt: Date?
    public var expiresAt: Date?
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, direction: ConnectRequestDirection, peer: PeerSummaryDTO, myCardID: UUID?, method: ConnectMethod,
                status: ConnectRequestStatus, eventName: String? = nil, place: String? = nil, createdAt: Date,
                respondedAt: Date? = nil, expiresAt: Date? = nil, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.direction = direction
        self.peer = peer
        self.myCardID = myCardID
        self.method = method
        self.status = status
        self.eventName = eventName
        self.place = place
        self.createdAt = createdAt
        self.respondedAt = respondedAt
        self.expiresAt = expiresAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }
}

/// A deleted record. Tombstones are kept server-side for at least 90 days (see sync docs).
public struct TombstoneDTO: Codable, Sendable, Hashable {
    public var type: SyncRecordType
    public var id: UUID
    public var deletedAt: Date

    public init(type: SyncRecordType, id: UUID, deletedAt: Date) {
        self.type = type
        self.id = id
        self.deletedAt = deletedAt
    }
}
