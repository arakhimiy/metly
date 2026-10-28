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
    /// The contact list (3.0.0), the only stored form. Missing on the wire → rebuilt from the legacy fields.
    public var contacts: [ContactEntry]
    public var defaultCardID: UUID?
    public var linksPaused: Bool
    public var notificationPrefs: NotificationPrefs
    public var privacySettings: PrivacySettings
    public var isSetupComplete: Bool
    public var createdAt: Date
    public var updatedAt: Date
    public var deletedAt: Date?

    public init(id: UUID, fullName: String, jobTitle: String, company: String, photoURL: URL? = nil, logoURL: URL? = nil,
                contactFields: [ContactField] = [], phoneLabel: PhoneLabel = .mobile, additionalPhones: [LabeledPhone] = [],
                contacts: [ContactEntry]? = nil,
                defaultCardID: UUID?, linksPaused: Bool, notificationPrefs: NotificationPrefs,
                privacySettings: PrivacySettings, isSetupComplete: Bool, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.photoURL = photoURL
        self.logoURL = logoURL
        self.contacts = contacts ?? .fromLegacy(fields: contactFields, phoneLabel: phoneLabel, additionalPhones: additionalPhones)
        self.defaultCardID = defaultCardID
        self.linksPaused = linksPaused
        self.notificationPrefs = notificationPrefs
        self.privacySettings = privacySettings
        self.isSetupComplete = isSetupComplete
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    /// Tolerant of payloads written before labelled phones existed (schema 2.0.0).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        fullName = try container.decode(String.self, forKey: .fullName)
        jobTitle = try container.decode(String.self, forKey: .jobTitle)
        company = try container.decode(String.self, forKey: .company)
        photoURL = try container.decodeIfPresent(URL.self, forKey: .photoURL)
        logoURL = try container.decodeIfPresent(URL.self, forKey: .logoURL)
        let fields = try container.decode([ContactField].self, forKey: .contactFields)
        let label = try container.decodePhoneLabel(forKey: .phoneLabel)
        let extras = try container.decodeLabeledPhones(forKey: .additionalPhones)
        contacts = try container.decodeContacts(forKey: .contacts)
            ?? .fromLegacy(fields: fields, phoneLabel: label, additionalPhones: extras)
        defaultCardID = try container.decodeIfPresent(UUID.self, forKey: .defaultCardID)
        linksPaused = try container.decode(Bool.self, forKey: .linksPaused)
        notificationPrefs = try container.decode(NotificationPrefs.self, forKey: .notificationPrefs)
        privacySettings = try container.decode(PrivacySettings.self, forKey: .privacySettings)
        isSetupComplete = try container.decode(Bool.self, forKey: .isSetupComplete)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, fullName, jobTitle, company, photoURL, logoURL, contactFields, phoneLabel, additionalPhones, contacts
        case defaultCardID, linksPaused, notificationPrefs, privacySettings, isSetupComplete, createdAt, updatedAt, deletedAt
    }

    /// Sends the list plus the legacy fields derived from it (the server still requires `contactFields`).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(jobTitle, forKey: .jobTitle)
        try container.encode(company, forKey: .company)
        try container.encodeIfPresent(photoURL, forKey: .photoURL)
        try container.encodeIfPresent(logoURL, forKey: .logoURL)
        try container.encode(contactFields, forKey: .contactFields)
        try container.encode(phoneLabel, forKey: .phoneLabel)
        try container.encode(additionalPhones, forKey: .additionalPhones)
        try container.encode(contacts, forKey: .contacts)
        try container.encodeIfPresent(defaultCardID, forKey: .defaultCardID)
        try container.encode(linksPaused, forKey: .linksPaused)
        try container.encode(notificationPrefs, forKey: .notificationPrefs)
        try container.encode(privacySettings, forKey: .privacySettings)
        try container.encode(isSetupComplete, forKey: .isSetupComplete)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    // MARK: Legacy one-per-kind view of `contacts` (older apps, the server's required fields)

    /// One field per original kind, display order (empty when the list has none).
    public var contactFields: [ContactField] {
        get { contacts.legacyFields }
        set { newValue.forEach { contacts.setFirst($0.kind, value: $0.value, privacy: $0.privacy) } }
    }

    /// Label of the first phone (`.mobile` without one).
    public var phoneLabel: PhoneLabel {
        get { contacts.legacyPhoneLabel }
        set { contacts.setFirstPhoneLabel(newValue) }
    }

    /// The phones after the first one (≤ `LabeledPhone.maxAdditional` on the wire).
    public var additionalPhones: [LabeledPhone] {
        get { contacts.legacyAdditionalPhones }
        set { contacts.setExtraPhones(newValue) }
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
    /// Profile contact entries the card shows; nil = a card from before 3.0.0 (`design.visibleFields`).
    /// Travels inside `design` on the wire (`design.visibleContacts`).
    public var visibleContacts: [UUID]?
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
                visibleContacts: [UUID]? = nil, publishState: CardPublishState = .draft, isReadOnly: Bool = false, isPaused: Bool = false,
                stats: CardStats? = nil, createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.name = name
        self.slug = slug
        self.url = url
        self.sortOrder = sortOrder
        self.design = design
        self.visibleContacts = visibleContacts
        self.publishState = publishState
        self.isReadOnly = isReadOnly
        self.isPaused = isPaused
        self.stats = stats
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, slug, url, sortOrder, design, publishState, isReadOnly, isPaused, stats, createdAt, updatedAt, deletedAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        slug = try container.decodeIfPresent(String.self, forKey: .slug)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        (design, visibleContacts) = try WireCardDesign.decode(from: container, forKey: .design)
        publishState = try container.decode(CardPublishState.self, forKey: .publishState)
        isReadOnly = try container.decode(Bool.self, forKey: .isReadOnly)
        isPaused = try container.decode(Bool.self, forKey: .isPaused)
        stats = try container.decodeIfPresent(CardStats.self, forKey: .stats)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(slug, forKey: .slug)
        try container.encodeIfPresent(url, forKey: .url)
        try container.encode(sortOrder, forKey: .sortOrder)
        try WireCardDesign.encode(design, visibleContacts: visibleContacts, to: &container, forKey: .design)
        try container.encode(publishState, forKey: .publishState)
        try container.encode(isReadOnly, forKey: .isReadOnly)
        try container.encode(isPaused, forKey: .isPaused)
        try container.encodeIfPresent(stats, forKey: .stats)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
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
    /// The contact list (3.0.0), the only stored form; `phone`…`linkedin`, `phoneLabel` and
    /// `additionalPhones` are views of it for older apps. Missing on the wire → rebuilt from them.
    public var contacts: [ContactEntry]
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
                phone: String = "", phoneLabel: PhoneLabel = .mobile, additionalPhones: [LabeledPhone] = [],
                email: String = "", telegram: String = "", website: String = "", linkedin: String = "",
                contacts: [ContactEntry]? = nil, avatarURL: URL? = nil, theirCard: CardSnapshot? = nil, mySharedCardID: UUID? = nil, source: ConnectionSource,
                context: MeetingContext, previousMeetings: [MeetingContext] = [], eventID: UUID? = nil, note: String = "",
                tags: [String] = [], isMerged: Bool = false, isPendingMerge: Bool = false, isBlocked: Bool = false,
                createdAt: Date, updatedAt: Date, deletedAt: Date? = nil) {
        self.id = id
        self.remoteUserID = remoteUserID
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.contacts = contacts ?? Self.legacyContacts(phone: phone, phoneLabel: phoneLabel, additionalPhones: additionalPhones,
                                                         email: email, telegram: telegram, website: website, linkedin: linkedin)
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

    /// Tolerant of payloads written before labelled phones (2.0.0) and contact lists (3.0.0) existed.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        remoteUserID = try container.decodeIfPresent(UUID.self, forKey: .remoteUserID)
        fullName = try container.decode(String.self, forKey: .fullName)
        jobTitle = try container.decode(String.self, forKey: .jobTitle)
        company = try container.decode(String.self, forKey: .company)
        contacts = try container.decodeContacts(forKey: .contacts)
            ?? Self.legacyContacts(phone: try container.decode(String.self, forKey: .phone),
                                   phoneLabel: try container.decodePhoneLabel(forKey: .phoneLabel),
                                   additionalPhones: try container.decodeLabeledPhones(forKey: .additionalPhones),
                                   email: try container.decode(String.self, forKey: .email),
                                   telegram: try container.decode(String.self, forKey: .telegram),
                                   website: try container.decode(String.self, forKey: .website),
                                   linkedin: try container.decode(String.self, forKey: .linkedin))
        avatarURL = try container.decodeIfPresent(URL.self, forKey: .avatarURL)
        theirCard = try container.decodeIfPresent(CardSnapshot.self, forKey: .theirCard)
        mySharedCardID = try container.decodeIfPresent(UUID.self, forKey: .mySharedCardID)
        source = try container.decode(ConnectionSource.self, forKey: .source)
        context = try container.decode(MeetingContext.self, forKey: .context)
        previousMeetings = try container.decode([MeetingContext].self, forKey: .previousMeetings)
        eventID = try container.decodeIfPresent(UUID.self, forKey: .eventID)
        note = try container.decode(String.self, forKey: .note)
        tags = try container.decode([String].self, forKey: .tags)
        isMerged = try container.decode(Bool.self, forKey: .isMerged)
        isPendingMerge = try container.decode(Bool.self, forKey: .isPendingMerge)
        isBlocked = try container.decode(Bool.self, forKey: .isBlocked)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        deletedAt = try container.decodeIfPresent(Date.self, forKey: .deletedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id, remoteUserID, fullName, jobTitle, company, phone, phoneLabel, additionalPhones, email, telegram, website
        case linkedin, contacts, avatarURL, theirCard, mySharedCardID, source, context, previousMeetings, eventID, note, tags
        case isMerged, isPendingMerge, isBlocked, createdAt, updatedAt, deletedAt
    }

    /// Sends the list plus the legacy fields derived from it (the server still requires them).
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(remoteUserID, forKey: .remoteUserID)
        try container.encode(fullName, forKey: .fullName)
        try container.encode(jobTitle, forKey: .jobTitle)
        try container.encode(company, forKey: .company)
        try container.encode(phone, forKey: .phone)
        try container.encode(phoneLabel, forKey: .phoneLabel)
        try container.encode(additionalPhones, forKey: .additionalPhones)
        try container.encode(email, forKey: .email)
        try container.encode(telegram, forKey: .telegram)
        try container.encode(website, forKey: .website)
        try container.encode(linkedin, forKey: .linkedin)
        try container.encode(contacts, forKey: .contacts)
        try container.encodeIfPresent(avatarURL, forKey: .avatarURL)
        try container.encodeIfPresent(theirCard, forKey: .theirCard)
        try container.encodeIfPresent(mySharedCardID, forKey: .mySharedCardID)
        try container.encode(source, forKey: .source)
        try container.encode(context, forKey: .context)
        try container.encode(previousMeetings, forKey: .previousMeetings)
        try container.encodeIfPresent(eventID, forKey: .eventID)
        try container.encode(note, forKey: .note)
        try container.encode(tags, forKey: .tags)
        try container.encode(isMerged, forKey: .isMerged)
        try container.encode(isPendingMerge, forKey: .isPendingMerge)
        try container.encode(isBlocked, forKey: .isBlocked)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(deletedAt, forKey: .deletedAt)
    }

    static func legacyContacts(phone: String, phoneLabel: PhoneLabel, additionalPhones: [LabeledPhone], email: String,
                               telegram: String, website: String, linkedin: String) -> [ContactEntry] {
        let fields = [ContactField(kind: .phone, value: phone, privacy: .connections),
                      ContactField(kind: .email, value: email, privacy: .connections),
                      ContactField(kind: .telegram, value: telegram, privacy: .connections),
                      ContactField(kind: .website, value: website, privacy: .connections),
                      ContactField(kind: .linkedin, value: linkedin, privacy: .connections)]
        return .fromLegacy(fields: fields, phoneLabel: phoneLabel,
                           additionalPhones: additionalPhones.map { LabeledPhone(id: $0.id, label: $0.label, value: $0.value, privacy: .connections) })
    }

    /// Replaces the list.
    public mutating func setContacts(_ list: [ContactEntry]) {
        contacts = list
    }

    // MARK: Legacy one-per-kind view of `contacts` (older apps, the server's required fields)

    public var phone: String {
        get { contacts.first(of: .phone)?.value ?? "" }
        set { contacts.setFirst(.phone, value: newValue, privacy: contacts.first(of: .phone) == nil ? .connections : nil) }
    }
    public var phoneLabel: PhoneLabel {
        get { contacts.legacyPhoneLabel }
        set { contacts.setFirstPhoneLabel(newValue) }
    }
    public var additionalPhones: [LabeledPhone] {
        get { contacts.legacyAdditionalPhones }
        set { contacts.setExtraPhones(newValue, privacy: .connections) }
    }
    public var email: String {
        get { contacts.first(of: .email)?.value ?? "" }
        set { contacts.setFirst(.email, value: newValue, privacy: contacts.first(of: .email) == nil ? .connections : nil) }
    }
    public var telegram: String {
        get { contacts.first(of: .telegram)?.value ?? "" }
        set { contacts.setFirst(.telegram, value: newValue, privacy: contacts.first(of: .telegram) == nil ? .connections : nil) }
    }
    public var website: String {
        get { contacts.first(of: .website)?.value ?? "" }
        set { contacts.setFirst(.website, value: newValue, privacy: contacts.first(of: .website) == nil ? .connections : nil) }
    }
    public var linkedin: String {
        get { contacts.first(of: .linkedin)?.value ?? "" }
        set { contacts.setFirst(.linkedin, value: newValue, privacy: contacts.first(of: .linkedin) == nil ? .connections : nil) }
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
