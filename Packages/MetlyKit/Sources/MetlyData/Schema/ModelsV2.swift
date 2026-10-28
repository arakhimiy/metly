import Foundation
import MetlyCore
import SwiftData

// FROZEN — the schema that shipped as 2.0.0 (TestFlight 1.0 (3), labelled phones). Never edit: SwiftData matches stores on
// disk against this exact shape to migrate them to the current schema (MetlyMigrationPlan).
// Stored properties and initialisers only; behaviour lives on the current version's models.

public enum MetlySchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Profile.self, Card.self, Connection.self, FollowUp.self, Event.self, ConnectRequest.self]
    }
}

extension MetlySchemaV2 {

    // MARK: Profile (singleton per signed-in user)

    @Model
    public final class Profile {
        @Attribute(.unique) public var id: UUID
        public var fullName: String
        public var jobTitle: String
        public var company: String
        @Attribute(.externalStorage) public var photoData: Data?
        @Attribute(.externalStorage) public var logoData: Data?
        public var contactFields: [ContactField]
        public var phoneLabelRaw: String = PhoneLabel.mobile.rawValue
        public var additionalPhones: [LabeledPhone] = []
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
                    contactFields: [ContactField] = ContactField.defaults, isSetupComplete: Bool = false) {
            self.id = id
            self.fullName = fullName
            self.jobTitle = jobTitle
            self.company = company
            self.contactFields = contactFields
            self.phoneLabelRaw = PhoneLabel.mobile.rawValue
            self.additionalPhones = []
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
        public var slug: String
        public var sortOrder: Int
        public var design: CardDesign
        public var publishStateRaw: String
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
        public var remoteUserID: UUID?
        public var fullName: String
        public var jobTitle: String
        public var company: String
        public var phone: String
        public var phoneLabelRaw: String = PhoneLabel.mobile.rawValue
        public var additionalPhones: [LabeledPhone] = []
        public var email: String
        public var telegram: String
        public var website: String
        public var linkedin: String
        @Attribute(.externalStorage) public var avatarData: Data?
        public var theirCard: CardSnapshot?
        public var mySharedCardID: UUID?
        public var sourceRaw: String
        public var context: MeetingContext
        public var previousMeetings: [MeetingContext]
        @Relationship(deleteRule: .nullify, inverse: \Event.connections) public var event: Event?
        public var note: String
        public var tags: [String]
        public var isMerged: Bool
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
            self.phone = ""
            self.phoneLabelRaw = PhoneLabel.mobile.rawValue
            self.additionalPhones = []
            self.email = ""
            self.telegram = ""
            self.website = ""
            self.linkedin = ""
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
