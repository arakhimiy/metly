import Foundation
import MetlyCore
import SwiftData

// FROZEN CONTRACT (orchestrator-owned). Feature agents read/write these models directly
// with SwiftData (`@Query`, `modelContext`), and MUST call `markChanged()` after mutating
// and `markDeleted()` instead of `modelContext.delete(_:)` so the sync engine sees it.
// Enum-typed properties are stored as raw strings so they work in #Predicate.

/// 4.0.0 — card face options (docs/design/card-templates-v2.md): `hidesJobTitle`, `hidesCompany` and
/// `logoStyleRaw` on Card. 3.0.0 (contact lists) is frozen in ModelsV3.swift.
public enum MetlySchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] {
        [Profile.self, Card.self, Connection.self, FollowUp.self, Event.self, ConnectRequest.self]
    }
}

public typealias Profile = MetlySchemaV4.Profile
public typealias Card = MetlySchemaV4.Card
public typealias Connection = MetlySchemaV4.Connection
public typealias FollowUp = MetlySchemaV4.FollowUp
public typealias Event = MetlySchemaV4.Event
public typealias ConnectRequest = MetlySchemaV4.ConnectRequest

/// Shared sync bookkeeping. Every model conforms.
public protocol SyncedRecord: PersistentModel {
    var id: UUID { get }
    var updatedAt: Date { get set }
    var syncStateRaw: String { get set }
    var deletedAt: Date? { get set }

    /// Predicates on the sync fields, spelled out per model (SyncPredicates.swift): a `#Predicate` over a
    /// generic `Model: SyncedRecord` traps inside SwiftData in optimised (Release) builds.
    static func syncStatePredicate(_ raw: String, equal: Bool) -> Predicate<Self>
    static func idPredicate(_ id: UUID) -> Predicate<Self>
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

extension MetlySchemaV4 {

    // MARK: Profile (singleton per signed-in user)

    @Model
    public final class Profile: SyncedRecord {
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

        // MARK: One-value-per-kind view of `contacts` (code written before 3.0.0)

        /// The first entry of each kind as a field (empty when there is none), every kind.
        public var contactFields: [ContactField] {
            get { ContactFieldKind.allCases.map(field) }
            set { newValue.forEach(setField) }
        }

        /// The first entry of `kind`, or an empty field with the kind's default privacy.
        public func field(_ kind: ContactFieldKind) -> ContactField {
            contacts.first(of: kind)?.field ?? ContactField(kind: kind)
        }

        /// Writes the first entry of the field's kind: updated in place, appended when there is none,
        /// removed when the value is empty.
        public func setField(_ field: ContactField) {
            contacts.setFirst(field.kind, value: field.value, privacy: field.privacy)
        }

        /// Label of the first phone (Mobile when there is none).
        public var phoneLabel: PhoneLabel {
            get { contacts.legacyPhoneLabel }
            set { contacts.setFirstPhoneLabel(newValue) }
        }

        /// The phones after the first one. Setting replaces them (kept right after the first phone).
        public var additionalPhones: [LabeledPhone] {
            get { Array(contacts.entries(of: .phone).dropFirst().map(\.labeledPhone)) }
            set { contacts.setExtraPhones(newValue) }
        }

        /// Every phone, first one first (empty values skipped). Privacy comes from each entry.
        public var allPhones: [LabeledPhone] { contacts.entries(of: .phone).map(\.labeledPhone) }

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
        /// Profile contact entries this card shows (`ContactEntry.id`); nil = a card from before 3.0.0,
        /// which shows the entries whose kind is in `design.visibleFields`. Added in 3.0.0.
        public var visibleContactIDs: [UUID]? = nil
        /// Per-card "Show on This Card" switches for the job title and company. Added in 4.0.0.
        public var hidesJobTitle: Bool = false
        public var hidesCompany: Bool = false
        /// `CardLogoStyle` raw value. Added in 4.0.0.
        public var logoStyleRaw: String = CardLogoStyle.original.rawValue
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

        /// The card's face options (title/company switches, logo style).
        public var faceOptions: CardFaceOptions {
            get {
                CardFaceOptions(showJobTitle: !hidesJobTitle, showCompany: !hidesCompany,
                                logoStyle: CardLogoStyle(rawValue: logoStyleRaw) ?? .original)
            }
            set {
                hidesJobTitle = !newValue.showJobTitle
                hidesCompany = !newValue.showCompany
                logoStyleRaw = newValue.logoStyle.rawValue
            }
        }

        /// nil until the server assigned a slug.
        public var url: URL? { slug.isEmpty ? nil : Brand.cardURL(slug: slug) }
    }

    // MARK: Connection (a person the owner met)

    @Model
    public final class Connection: SyncedRecord {
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

        public var source: ConnectionSource {
            get { ConnectionSource(rawValue: sourceRaw) ?? .manual }
            set { sourceRaw = newValue.rawValue }
        }

        // MARK: One-value-per-kind view of `contacts` (code written before 3.0.0)

        public var phone: String {
            get { value(for: .phone) }
            set { setValue(newValue, for: .phone) }
        }
        public var email: String {
            get { value(for: .email) }
            set { setValue(newValue, for: .email) }
        }
        public var telegram: String {
            get { value(for: .telegram) }
            set { setValue(newValue, for: .telegram) }
        }
        public var website: String {
            get { value(for: .website) }
            set { setValue(newValue, for: .website) }
        }
        public var linkedin: String {
            get { value(for: .linkedin) }
            set { setValue(newValue, for: .linkedin) }
        }

        /// Value of the first entry of `kind`, or "".
        public func value(for kind: ContactFieldKind) -> String {
            contacts.first(of: kind)?.value ?? ""
        }

        /// Writes the first entry of `kind`: updated in place, appended when there is none, removed when empty.
        public func setValue(_ value: String, for kind: ContactFieldKind) {
            contacts.setFirst(kind, value: value, privacy: contacts.first(of: kind) == nil ? .connections : nil)
        }

        /// The first entry of each kind, non-empty only, in kind order.
        public var availableFields: [ContactField] {
            ContactFieldKind.allCases.compactMap { contacts.first(of: $0).map { ContactField(kind: $0.kind, value: $0.value, privacy: .connections) } }
        }

        /// Label of the first phone (Mobile when there is none).
        public var phoneLabel: PhoneLabel {
            get { contacts.legacyPhoneLabel }
            set { contacts.setFirstPhoneLabel(newValue) }
        }

        /// The phones after the first one. Setting replaces them (kept right after the first phone).
        public var additionalPhones: [LabeledPhone] {
            get { Array(contacts.entries(of: .phone).dropFirst().map(\.labeledPhone)) }
            set { contacts.setExtraPhones(newValue, privacy: .connections) }
        }

        /// Every phone, first one first, empty values skipped.
        public var allPhones: [LabeledPhone] { contacts.entries(of: .phone).map(\.labeledPhone) }

        /// The number most likely to reach the person on a messenger (mobile first, then the primary).
        public var mobilePhone: String? {
            allPhones.first { $0.label == .mobile }?.value ?? allPhones.first?.value
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
    public static var schemas: [any VersionedSchema.Type] {
        [MetlySchemaV1.self, MetlySchemaV2.self, MetlySchemaV3.self, MetlySchemaV4.self]
    }
    public static var stages: [MigrationStage] { [v1ToV2, v2ToV3, v3ToV4] }

    /// 3 → 4 only adds Card attributes with defaults.
    static let v3ToV4 = MigrationStage.lightweight(fromVersion: MetlySchemaV3.self, toVersion: MetlySchemaV4.self)

    /// 1 → 2 only adds attributes with defaults, so SwiftData migrates it in place.
    static let v1ToV2 = MigrationStage.lightweight(fromVersion: MetlySchemaV1.self, toVersion: MetlySchemaV2.self)

    /// 2 → 3 renames the per-kind columns to `legacy…` and adds `contacts`, then builds each list from
    /// the legacy values (docs/api/CONTACTS.md "Legacy → list").
    static let v2ToV3 = MigrationStage.custom(fromVersion: MetlySchemaV2.self, toVersion: MetlySchemaV3.self,
                                              willMigrate: nil, didMigrate: { context in
        try migrateContacts(in: context)
    })

    static func migrateContacts(in context: ModelContext) throws {
        for profile in try context.fetch(FetchDescriptor<MetlySchemaV3.Profile>()) where profile.contacts.isEmpty {
            profile.contacts = .fromLegacy(fields: profile.legacyContactFields,
                                           phoneLabel: PhoneLabel(rawValue: profile.legacyPhoneLabelRaw) ?? .mobile,
                                           additionalPhones: profile.legacyAdditionalPhones)
        }
        for person in try context.fetch(FetchDescriptor<MetlySchemaV3.Connection>()) where person.contacts.isEmpty {
            let fields = [
                ContactField(kind: .phone, value: person.legacyPhone, privacy: .connections),
                ContactField(kind: .email, value: person.legacyEmail, privacy: .connections),
                ContactField(kind: .telegram, value: person.legacyTelegram, privacy: .connections),
                ContactField(kind: .website, value: person.legacyWebsite, privacy: .connections),
                ContactField(kind: .linkedin, value: person.legacyLinkedin, privacy: .connections),
            ]
            person.contacts = .fromLegacy(fields: fields, phoneLabel: PhoneLabel(rawValue: person.legacyPhoneLabelRaw) ?? .mobile,
                                          additionalPhones: person.legacyAdditionalPhones.map {
                                              LabeledPhone(id: $0.id, label: $0.label, value: $0.value, privacy: .connections)
                                          })
        }
        try context.save()
    }
}
