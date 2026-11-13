import Foundation
import MetlyCore
import SwiftData

// FROZEN — the schema that shipped as 3.0.0 (contact lists). Never edit: SwiftData matches stores on disk against
// this exact shape to migrate them to the current schema (MetlyMigrationPlan).
// Stored properties and initialisers only; behaviour lives on the current version's models.

public enum MetlySchemaV3: VersionedSchema {
    public static let versionIdentifier = Schema.Version(3, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Profile.self, Card.self, Connection.self, FollowUp.self, Event.self, ConnectRequest.self]
    }
}

extension MetlySchemaV3 {

    // MARK: Profile (singleton per signed-in user)

    @Model
    public final class Profile {
        @Attribute(.unique) public var id: UUID
        public var fullName: String
        public var jobTitle: String
        public var company: String
        @Attribute(.externalStorage) public var photoData: Data?
        @Attribute(.externalStorage) public var logoData: Data?
        /// The owner's contact details in their order (≤ `ContactEntry.maxCount`). Added in 3.0.0.
        public var contacts: [ContactEntry] = []
        /// 1.0.0–2.0.0 storage, only read by the 2.0.0 → 3.0.0 migration. Use `contacts`.
        @Attribute(originalName: "contactFields") public var legacyContactFields: [ContactField] = []
        @Attribute(originalName: "phoneLabelRaw") public var legacyPhoneLabelRaw: String = PhoneLabel.mobile.rawValue
        @Attribute(originalName: "additionalPhones") public var legacyAdditionalPhones: [LabeledPhone] = []
        public var defaultCardID: UUID?
        public var linksPaused: Bool
        public var notificationPrefs: NotificationPrefs
        public var privacySettings: PrivacySettings
        public var isSetupComplete: Bool
        public var createdAt: Date
        public var updatedAt: Date
        public var syncStateRaw: String
        public var deletedAt: Date?

        public init(id: UUID = UUID(), fullName: String = "", jobTitle: String = "", company: String = "",
                    contactFields: [ContactField] = [], contacts: [ContactEntry] = [], isSetupComplete: Bool = false) {
            self.id = id
            self.fullName = fullName
            self.jobTitle = jobTitle
            self.company = company
            self.contacts = contacts + [ContactEntry].fromLegacy(
                fields: contactFields, phoneLabel: .mobile, additionalPhones: [],
                keeping: contactFields.filter { !$0.kind.isLegacy }.map { ContactEntry(kind: $0.kind, value: $0.value, privacy: $0.privacy) })
            self.legacyContactFields = []
            self.legacyPhoneLabelRaw = PhoneLabel.mobile.rawValue
            self.legacyAdditionalPhones = []
            self.linksPaused = false
            self.notificationPrefs = NotificationPrefs()
            self.privacySettings = PrivacySettings()
            self.isSetupComplete = isSetupComplete
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.pendingUpsert.rawValue
        }
    }

    // MARK: Card (the owner's own cards)

    @Model
    public final class Card {
        @Attribute(.unique) public var id: UUID
        public var name: String
        /// Server-assigned; empty until first publish succeeds.
        public var slug: String
        public var sortOrder: Int
        public var design: CardDesign
        /// Profile contact entries this card shows (`ContactEntry.id`); nil = a card from before 3.0.0,
        /// which shows the entries whose kind is in `design.visibleFields`. Added in 3.0.0.
        public var visibleContactIDs: [UUID]? = nil
        public var publishStateRaw: String
        /// Pro downgrade beyond the Free card limit.
        public var isReadOnly: Bool
        public var stats: CardStats
        public var createdAt: Date
        public var updatedAt: Date
        public var syncStateRaw: String
        public var deletedAt: Date?

        public init(id: UUID = UUID(), name: String, slug: String = "", sortOrder: Int = 0, design: CardDesign = CardDesign()) {
            self.id = id
            self.name = name
            self.slug = slug
            self.sortOrder = sortOrder
            self.design = design
            self.publishStateRaw = CardPublishState.draft.rawValue
            self.isReadOnly = false
            self.stats = CardStats()
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.pendingUpsert.rawValue
        }
    }

    // MARK: Connection (a person the owner met)

    @Model
    public final class Connection {
        @Attribute(.unique) public var id: UUID
        /// Set when the person is a Nameshake user (enables their card & connections-only fields).
        public var remoteUserID: UUID?
        public var fullName: String
        public var jobTitle: String
        public var company: String
        /// The person's contact details in order (≤ `ContactEntry.maxCount`). Added in 3.0.0.
        public var contacts: [ContactEntry] = []
        /// 1.0.0–2.0.0 storage, only read by the 2.0.0 → 3.0.0 migration. Use `contacts`.
        @Attribute(originalName: "phone") public var legacyPhone: String = ""
        @Attribute(originalName: "phoneLabelRaw") public var legacyPhoneLabelRaw: String = PhoneLabel.mobile.rawValue
        @Attribute(originalName: "additionalPhones") public var legacyAdditionalPhones: [LabeledPhone] = []
        @Attribute(originalName: "email") public var legacyEmail: String = ""
        @Attribute(originalName: "telegram") public var legacyTelegram: String = ""
        @Attribute(originalName: "website") public var legacyWebsite: String = ""
        @Attribute(originalName: "linkedin") public var legacyLinkedin: String = ""
        @Attribute(.externalStorage) public var avatarData: Data?
        public var theirCard: CardSnapshot?
        /// "You shared your Work card with …"
        public var mySharedCardID: UUID?
        public var sourceRaw: String
        public var context: MeetingContext
        public var previousMeetings: [MeetingContext]
        @Relationship(deleteRule: .nullify, inverse: \Event.connections) public var event: Event?
        public var note: String
        public var tags: [String]
        /// A web share-back merged into a "Who did you just meet?" record.
        public var isMerged: Bool
        /// A "just met" placeholder waiting for a share-back.
        public var isPendingMerge: Bool
        public var isBlocked: Bool
        @Relationship(deleteRule: .cascade, inverse: \FollowUp.connection) public var followUps: [FollowUp]
        public var createdAt: Date
        public var updatedAt: Date
        public var syncStateRaw: String
        public var deletedAt: Date?

        public init(id: UUID = UUID(), fullName: String, jobTitle: String = "", company: String = "",
                    source: ConnectionSource, context: MeetingContext = MeetingContext()) {
            self.id = id
            self.fullName = fullName
            self.jobTitle = jobTitle
            self.company = company
            self.contacts = []
            self.legacyPhone = ""
            self.legacyPhoneLabelRaw = PhoneLabel.mobile.rawValue
            self.legacyAdditionalPhones = []
            self.legacyEmail = ""
            self.legacyTelegram = ""
            self.legacyWebsite = ""
            self.legacyLinkedin = ""
            self.sourceRaw = source.rawValue
            self.context = context
            self.previousMeetings = []
            self.note = ""
            self.tags = []
            self.isMerged = false
            self.isPendingMerge = false
            self.isBlocked = false
            self.followUps = []
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.pendingUpsert.rawValue
        }
    }

    // MARK: FollowUp (reminder)

    @Model
    public final class FollowUp {
        @Attribute(.unique) public var id: UUID
        public var title: String
        public var channelRaw: String
        public var dueAt: Date
        public var isDone: Bool
        public var completedAt: Date?
        public var connection: Connection?
        public var createdAt: Date
        public var updatedAt: Date
        public var syncStateRaw: String
        public var deletedAt: Date?

        public init(id: UUID = UUID(), title: String = "Follow up", channel: FollowUpChannel, dueAt: Date, connection: Connection? = nil) {
            self.id = id
            self.title = title
            self.channelRaw = channel.rawValue
            self.dueAt = dueAt
            self.isDone = false
            self.connection = connection
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.pendingUpsert.rawValue
        }
    }

    // MARK: Event (event mode)

    @Model
    public final class Event {
        @Attribute(.unique) public var id: UUID
        public var name: String
        public var place: String
        public var city: String
        public var startDate: Date
        public var endDate: Date
        /// "Card to Share" while the event is active.
        public var cardID: UUID?
        public var statusRaw: String
        public var calendarEventIdentifier: String?
        public var endedAt: Date?
        public var connections: [Connection]
        public var createdAt: Date
        public var updatedAt: Date
        public var syncStateRaw: String
        public var deletedAt: Date?

        public init(id: UUID = UUID(), name: String, place: String = "", city: String = "",
                    startDate: Date = .now, endDate: Date = .now, cardID: UUID? = nil) {
            self.id = id
            self.name = name
            self.place = place
            self.city = city
            self.startDate = startDate
            self.endDate = endDate
            self.cardID = cardID
            self.statusRaw = EventStatus.active.rawValue
            self.connections = []
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.pendingUpsert.rawValue
        }
    }

    // MARK: ConnectRequest (server-driven cache of in-app connect requests)

    @Model
    public final class ConnectRequest {
        @Attribute(.unique) public var id: UUID
        public var directionRaw: String
        public var peerUserID: UUID
        public var peerName: String
        public var peerTitle: String
        public var peerCompany: String
        public var peerCard: CardSnapshot?
        /// The owner's card offered (outgoing) or to return on accept (incoming).
        public var myCardID: UUID?
        public var methodRaw: String
        public var statusRaw: String
        public var eventName: String?
        public var createdAt: Date
        public var respondedAt: Date?
        public var expiresAt: Date?
        public var updatedAt: Date
        public var syncStateRaw: String
        public var deletedAt: Date?

        public init(id: UUID = UUID(), direction: ConnectRequestDirection, peerUserID: UUID, peerName: String,
                    peerTitle: String = "", peerCompany: String = "", peerCard: CardSnapshot? = nil,
                    myCardID: UUID? = nil, method: ConnectMethod, eventName: String? = nil) {
            self.id = id
            self.directionRaw = direction.rawValue
            self.peerUserID = peerUserID
            self.peerName = peerName
            self.peerTitle = peerTitle
            self.peerCompany = peerCompany
            self.peerCard = peerCard
            self.myCardID = myCardID
            self.methodRaw = method.rawValue
            self.statusRaw = ConnectRequestStatus.pending.rawValue
            self.eventName = eventName
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.synced.rawValue
        }
    }
}
