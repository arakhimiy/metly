import Foundation
import MetlyCore

/// Plain values read from the app's store, from which `WidgetSnapshotBuilder` makes a snapshot.
///
/// The app fills it from SwiftData (`ModelContext.currentProfile()`, `Card.live`, `FollowUp.open`,
/// `Connection.live`, `cardToShare()`) — see `AppWidgetSnapshotSource` in the app target. Keeping the
/// model types out of this module keeps the widget extension free of SwiftData.
nonisolated public struct WidgetSnapshotInput: Sendable {
    public struct Owner: Sendable {
        public var fullName: String
        public var jobTitle: String
        public var company: String
        public var photoData: Data?
        public var logoData: Data?
        /// Every contact field with its privacy (filtered to Public by the builder).
        public var contactFields: [ContactField]
        /// Label of the primary phone in `contactFields` (`Profile.phoneLabel`).
        public var phoneLabel: PhoneLabel
        /// Extra numbers with their privacy (`Profile.additionalPhones`, filtered to Public by the builder).
        public var additionalPhones: [LabeledPhone]
        /// The contact list with privacy (`Profile.contacts`); nil = rebuilt from the three fields above.
        public var explicitContacts: [ContactEntry]?
        public var linksPaused: Bool

        public var contacts: [ContactEntry] {
            explicitContacts ?? .fromLegacy(fields: contactFields, phoneLabel: phoneLabel, additionalPhones: additionalPhones)
        }

        public init(fullName: String, jobTitle: String = "", company: String = "", photoData: Data? = nil,
                    logoData: Data? = nil, contactFields: [ContactField] = [], phoneLabel: PhoneLabel = .mobile,
                    additionalPhones: [LabeledPhone] = [], contacts: [ContactEntry]? = nil, linksPaused: Bool = false) {
            self.fullName = fullName
            self.jobTitle = jobTitle
            self.company = company
            self.photoData = photoData
            self.logoData = logoData
            self.contactFields = contactFields
            self.phoneLabel = phoneLabel
            self.additionalPhones = additionalPhones
            self.explicitContacts = contacts
            self.linksPaused = linksPaused
        }
    }

    public struct Card: Sendable {
        public var id: UUID
        public var name: String
        /// Empty until the server assigned one.
        public var slug: String
        public var sortOrder: Int
        public var design: CardDesign
        /// Entries the card shows (`Card.visibleContactIDs`); nil = a card from before 3.0.0 (`design.visibleFields`).
        public var visibleContactIDs: [UUID]?
        /// `Card.faceOptions`.
        public var faceOptions: CardFaceOptions

        public init(id: UUID, name: String, slug: String = "", sortOrder: Int = 0, design: CardDesign = CardDesign(),
                    visibleContactIDs: [UUID]? = nil, faceOptions: CardFaceOptions = CardFaceOptions()) {
            self.id = id
            self.name = name
            self.slug = slug
            self.sortOrder = sortOrder
            self.design = design
            self.visibleContactIDs = visibleContactIDs
            self.faceOptions = faceOptions
        }
    }

    public struct FollowUp: Sendable {
        public var id: UUID
        public var title: String
        public var dueAt: Date
        public var channel: FollowUpChannel
        public var personName: String?
        public var connectionID: UUID?
        /// "{event or company}" of the person.
        public var personContext: String?

        public init(id: UUID, title: String, dueAt: Date, channel: FollowUpChannel, personName: String? = nil,
                    connectionID: UUID? = nil, personContext: String? = nil) {
            self.id = id
            self.title = title
            self.dueAt = dueAt
            self.channel = channel
            self.personName = personName
            self.connectionID = connectionID
            self.personContext = personContext
        }
    }

    public var owner: Owner
    public var cards: [Card]
    public var defaultCardID: UUID?
    /// `ModelContext.cardToShare()` — the active event's card, else the default card.
    public var shareCardID: UUID?
    /// Open (not done, not deleted) follow-ups of people who are not deleted.
    public var openFollowUps: [FollowUp]
    /// `createdAt` of live connections (older ones are ignored by the builder).
    public var connectionDates: [Date]
    public var activeEventName: String?

    public init(owner: Owner, cards: [Card] = [], defaultCardID: UUID? = nil, shareCardID: UUID? = nil,
                openFollowUps: [FollowUp] = [], connectionDates: [Date] = [], activeEventName: String? = nil) {
        self.owner = owner
        self.cards = cards
        self.defaultCardID = defaultCardID
        self.shareCardID = shareCardID
        self.openFollowUps = openFollowUps
        self.connectionDates = connectionDates
        self.activeEventName = activeEventName
    }
}
