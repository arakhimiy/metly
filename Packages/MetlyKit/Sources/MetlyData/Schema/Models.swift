import Foundation
import MetlyCore
import SwiftData

// FROZEN CONTRACT (orchestrator-owned). Feature agents read/write these models directly
// with SwiftData (`@Query`, `modelContext`), and MUST call `markChanged()` after mutating
// and `markDeleted()` instead of `modelContext.delete(_:)` so the sync engine sees it.
// Enum-typed properties are stored as raw strings so they work in #Predicate.

public enum MetlySchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Profile.self, Card.self, Connection.self, FollowUp.self, Event.self, ConnectRequest.self]
    }
}

public typealias Profile = MetlySchemaV1.Profile
public typealias Card = MetlySchemaV1.Card
public typealias Connection = MetlySchemaV1.Connection
public typealias FollowUp = MetlySchemaV1.FollowUp
public typealias Event = MetlySchemaV1.Event
public typealias ConnectRequest = MetlySchemaV1.ConnectRequest

/// Shared sync bookkeeping. Every model conforms.
public protocol SyncedRecord: PersistentModel {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var syncStateRaw: String { get set }
    var deletedAt: Date? { get set }
}

public extension SyncedRecord {
    var syncState: SyncState {
        get { SyncState(rawValue: syncStateRaw) ?? .synced }
        set { syncStateRaw = newValue.rawValue }
    }

    /// Call after every user edit.
    func markChanged() {
        updatedAt = .now
        syncStateRaw = SyncState.pendingUpsert.rawValue
    }

    /// Soft delete (tombstone); the sync engine hard-deletes after the server confirms.
    func markDeleted() {
        deletedAt = .now
        updatedAt = .now
        syncStateRaw = SyncState.pendingDelete.rawValue
    }

    /// Undo a soft delete (e.g. "Remove" → Undo toast).
    func restore() {
        deletedAt = nil
        markChanged()
    }

    var isDeleted: Bool { deletedAt != nil }
}

extension MetlySchemaV1 {

    // MARK: Profile (singleton per signed-in user)

    @Model
    public final class Profile: SyncedRecord {
        @Attribute(.unique) public var id: UUID
        public var fullName: String
        public var jobTitle: String
        public var company: String
        @Attribute(.externalStorage) public var photoData: Data?
        @Attribute(.externalStorage) public var logoData: Data?
        /// One entry per ContactFieldKind, display order.
        public var contactFields: [ContactField]
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
            self.linksPaused = false
            self.notificationPrefs = NotificationPrefs()
            self.privacySettings = PrivacySettings()
            self.isSetupComplete = isSetupComplete
            self.createdAt = .now
            self.updatedAt = .now
            self.syncStateRaw = SyncState.pendingUpsert.rawValue
        }

        public func field(_ kind: ContactFieldKind) -> ContactField {
            contactFields.first { $0.kind == kind } ?? ContactField(kind: kind)
        }

        public func setField(_ field: ContactField) {
            if let index = contactFields.firstIndex(where: { $0.kind == field.kind }) {
                contactFields[index] = field
            } else {
                contactFields.append(field)
                contactFields.sort { ContactFieldKind.allCases.firstIndex(of: $0.kind)! < ContactFieldKind.allCases.firstIndex(of: $1.kind)! }
            }
        }

        /// A user edit of one field's value (its privacy stays); queues the profile for sync.
        public func setContactValue(_ value: String, for kind: ContactFieldKind) {
            var updated = field(kind)
            guard updated.value != value else { return }
            updated.value = value
            setField(updated)
            markChanged()
        }
    }

    // MARK: Card (the owner's own cards)

    @Model
    public final class Card: SyncedRecord {
        @Attribute(.unique) public var id: UUID
        public var name: String
        /// Server-assigned; empty until first publish succeeds.
        public var slug: String
        public var sortOrder: Int
        public var design: CardDesign
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

        public var publishState: CardPublishState {
            get { CardPublishState(rawValue: publishStateRaw) ?? .draft }
            set { publishStateRaw = newValue.rawValue }
        }

        /// nil until the server assigned a slug.
        public var url: URL? { slug.isEmpty ? nil : Brand.cardURL(slug: slug) }
    }

    // MARK: Connection (a person the owner met)

    @Model
    public final class Connection: SyncedRecord {
        @Attribute(.unique) public var id: UUID
        /// Set when the person is a Metly user (enables their card & connections-only fields).
        public var remoteUserID: UUID?
        public var fullName: String
        public var jobTitle: String
        public var company: String
        public var phone: String
        public var email: String
        public var telegram: String
        public var website: String
        public var linkedin: String
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
            self.phone = ""
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

        public var source: ConnectionSource {
            get { ConnectionSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        public func value(for kind: ContactFieldKind) -> String {
            switch kind {
            case .phone: phone
            case .email: email
            case .telegram: telegram
            case .website: website
            case .linkedin: linkedin
            }
        }

        public func setValue(_ value: String, for kind: ContactFieldKind) {
            switch kind {
            case .phone: phone = value
            case .email: email = value
            case .telegram: telegram = value
            case .website: website = value
            case .linkedin: linkedin = value
            }
        }

        /// Non-empty contact values in display order.
        public var availableFields: [ContactField] {
            ContactFieldKind.allCases.compactMap { kind in
                let value = value(for: kind)
                return value.isEmpty ? nil : ContactField(kind: kind, value: value, privacy: .connections)
            }
        }

        public var openFollowUp: FollowUp? {
            followUps.filter { !$0.isDone && !$0.isDeleted }.min { $0.dueAt < $1.dueAt }
        }
    }

    // MARK: FollowUp (reminder)

    @Model
    public final class FollowUp: SyncedRecord {
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

        public var channel: FollowUpChannel {
            get { FollowUpChannel(rawValue: channelRaw) ?? .telegram }
            set { channelRaw = newValue.rawValue }
        }
    }

    // MARK: Event (event mode)

    @Model
    public final class Event: SyncedRecord {
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

        public var status: EventStatus {
            get { EventStatus(rawValue: statusRaw) ?? .active }
            set { statusRaw = newValue.rawValue }
        }

        public var isActive: Bool { status == .active && !isDeleted }
    }

    // MARK: ConnectRequest (server-driven cache of in-app connect requests)

    @Model
    public final class ConnectRequest: SyncedRecord {
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

        public var direction: ConnectRequestDirection {
            get { ConnectRequestDirection(rawValue: directionRaw) ?? .incoming }
            set { directionRaw = newValue.rawValue }
        }
        public var method: ConnectMethod {
            get { ConnectMethod(rawValue: methodRaw) ?? .nearby }
            set { methodRaw = newValue.rawValue }
        }
        public var status: ConnectRequestStatus {
            get { ConnectRequestStatus(rawValue: statusRaw) ?? .pending }
            set { statusRaw = newValue.rawValue }
        }
    }
}

public enum MetlyMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [MetlySchemaV1.self] }
    public static var stages: [MigrationStage] { [] }
}
