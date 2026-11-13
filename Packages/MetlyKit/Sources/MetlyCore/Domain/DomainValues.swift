import Foundation

public struct ContactField: Codable, Hashable, Sendable, Identifiable {
    public var kind: ContactFieldKind
    public var value: String
    public var privacy: FieldPrivacy

    public var id: ContactFieldKind { kind }

    public init(kind: ContactFieldKind, value: String = "", privacy: FieldPrivacy? = nil) {
        self.kind = kind
        self.value = value
        self.privacy = privacy ?? kind.defaultPrivacy
    }

    public var isEmpty: Bool { value.trimmingCharacters(in: .whitespaces).isEmpty }

    /// One empty field per kind, in display order, with default privacy.
    public static var defaults: [ContactField] { ContactFieldKind.allCases.map { ContactField(kind: $0) } }
}

/// One phone number with its label (Mobile / Work / Home / Other) and privacy.
/// The primary phone stays in `ContactField(.phone)`; these are the extra ones (schema 2.0.0).
public struct LabeledPhone: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var label: PhoneLabel
    public var value: String
    public var privacy: FieldPrivacy

    /// Server-validated: at most this many extra phones per profile / connection.
    public static let maxAdditional = 5
    /// Server-validated: a phone value is at most this many characters.
    public static let maxValueLength = 40

    /// Stable id used when the primary phone is presented as a `LabeledPhone` (`allPhones`).
    public static let primaryID = UUID(uuidString: "00000000-0000-0000-0000-00000000F001")!

    public init(id: UUID = UUID(), label: PhoneLabel = .work, value: String = "", privacy: FieldPrivacy = .connections) {
        self.id = id
        self.label = label
        self.value = value
        self.privacy = privacy
    }

    public var isEmpty: Bool { value.trimmingCharacters(in: .whitespaces).isEmpty }
    public var isPrimary: Bool { id == Self.primaryID }
}

/// One entry of a contact list (schema 3.0.0, docs/api/CONTACTS.md): any kind, several of the same kind,
/// in the user's order. Profiles and connections hold at most `maxCount`.
public struct ContactEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: ContactFieldKind
    /// Mobile / Work / Home / Other — phones only; nil for every other kind.
    public var label: PhoneLabel?
    public var value: String
    public var privacy: FieldPrivacy

    /// Server-validated: at most this many entries per profile / connection.
    public static let maxCount = 10

    public init(id: UUID = UUID(), kind: ContactFieldKind, label: PhoneLabel? = nil, value: String = "",
                privacy: FieldPrivacy? = nil) {
        self.id = id
        self.kind = kind
        self.label = kind == .phone ? (label ?? .mobile) : nil
        self.value = value
        self.privacy = privacy ?? kind.defaultPrivacy
    }

    public var isEmpty: Bool { value.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Server-validated: the longest value of a kind.
    public static func maxLength(for kind: ContactFieldKind) -> Int {
        switch kind {
        case .phone, .whatsapp: LabeledPhone.maxValueLength
        case .website, .linkedin: 500
        case .address: 300
        case .email, .telegram, .instagram: 200
        }
    }

    /// Fixed id of the entry rebuilt from a legacy primary field (first value of the kind), so a card's
    /// selection keeps pointing at it across the 2.0.0 → 3.0.0 migration and older apps' edits.
    public static func primaryID(for kind: ContactFieldKind) -> UUID {
        let suffix: String
        switch kind {
        case .phone: suffix = "F001"
        case .email: suffix = "F002"
        case .telegram: suffix = "F003"
        case .website: suffix = "F004"
        case .linkedin: suffix = "F005"
        case .whatsapp: suffix = "F006"
        case .instagram: suffix = "F007"
        case .address: suffix = "F008"
        }
        return UUID(uuidString: "00000000-0000-0000-0000-00000000\(suffix)")!
    }

    /// As a `ContactField` (legacy, one value per kind).
    public var field: ContactField { ContactField(kind: kind, value: value, privacy: privacy) }

    /// As a `LabeledPhone` (phones only).
    public var labeledPhone: LabeledPhone {
        LabeledPhone(id: id, label: label ?? .mobile, value: value, privacy: privacy)
    }

    /// Normalised form two values of the same kind compare by: digits for phone numbers, else the
    /// lower-cased value without a leading "@" and surrounding spaces.
    public var matchKey: String {
        if kind.isPhoneNumber { return value.filter(\.isNumber) }
        var key = value.trimmingCharacters(in: .whitespaces).lowercased()
        if key.hasPrefix("@") { key.removeFirst() }
        return key
    }
}

public extension Array where Element == ContactEntry {
    /// Non-empty entries, at most `ContactEntry.maxCount`.
    var trimmedForSync: [ContactEntry] {
        Array(filter { !$0.isEmpty }.prefix(ContactEntry.maxCount))
    }

    func first(of kind: ContactFieldKind) -> ContactEntry? { first { $0.kind == kind && !$0.isEmpty } }

    func entries(of kind: ContactFieldKind) -> [ContactEntry] { filter { $0.kind == kind && !$0.isEmpty } }

    /// The list as the legacy wire fields describe it (docs/api/CONTACTS.md "List → legacy").
    var legacyFields: [ContactField] {
        ContactFieldKind.legacy.map { kind in first(of: kind)?.field ?? ContactField(kind: kind) }
    }

    var legacyPhoneLabel: PhoneLabel { first(of: .phone)?.label ?? .mobile }

    var legacyAdditionalPhones: [LabeledPhone] {
        entries(of: .phone).dropFirst().prefix(LabeledPhone.maxAdditional).map(\.labeledPhone)
    }

    /// Rebuilds a list from the legacy fields ("Legacy → list"): the primary phone, the extra phones,
    /// then email, telegram, website, linkedin; `keeping` entries the legacy fields cannot express
    /// (WhatsApp, Instagram, second emails…) are appended in their order. Capped at `maxCount`.
    static func fromLegacy(fields: [ContactField], phoneLabel: PhoneLabel, additionalPhones: [LabeledPhone],
                           keeping existing: [ContactEntry] = []) -> [ContactEntry] {
        func primary(_ kind: ContactFieldKind) -> ContactEntry? {
            guard let field = fields.first(where: { $0.kind == kind }), !field.isEmpty else { return nil }
            return ContactEntry(id: ContactEntry.primaryID(for: kind), kind: kind,
                                label: kind == .phone ? phoneLabel : nil, value: field.value, privacy: field.privacy)
        }
        var list: [ContactEntry] = []
        if let phone = primary(.phone) { list.append(phone) }
        list += additionalPhones.filter { !$0.isEmpty }.map {
            ContactEntry(id: $0.id, kind: .phone, label: $0.label, value: $0.value, privacy: $0.privacy)
        }
        for kind in [ContactFieldKind.email, .telegram, .website, .linkedin] {
            if let entry = primary(kind) { list.append(entry) }
        }
        list += existing.droppingLegacyExpressible()
        var seen = Set<UUID>()
        return Array(list.filter { seen.insert($0.id).inserted }.prefix(ContactEntry.maxCount))
    }

    // MARK: One-value-per-kind writes (code written before 3.0.0, legacy wire fields)

    /// Writes the first entry of `kind`: updated in place, added when there is none (a phone goes first,
    /// anything else last), removed when `value` is empty. `privacy` nil keeps the entry's own.
    mutating func setFirst(_ kind: ContactFieldKind, value: String, privacy: FieldPrivacy? = nil) {
        let isEmpty = value.trimmingCharacters(in: .whitespaces).isEmpty
        if let index = firstIndex(where: { $0.kind == kind && !$0.isEmpty }) {
            if isEmpty {
                remove(at: index)
            } else {
                self[index].value = value
                if let privacy { self[index].privacy = privacy }
            }
        } else if !isEmpty {
            let entry = ContactEntry(kind: kind, value: value, privacy: privacy)
            if kind == .phone { insert(entry, at: 0) } else { append(entry) }
        }
    }

    /// Labels the first phone (nothing to label without one).
    mutating func setFirstPhoneLabel(_ label: PhoneLabel) {
        guard let index = firstIndex(where: { $0.kind == .phone && !$0.isEmpty }) else { return }
        self[index].label = label
    }

    /// Replaces the phones after the first one, kept right after it. `privacy` overrides theirs (connections).
    mutating func setExtraPhones(_ phones: [LabeledPhone], privacy: FieldPrivacy? = nil) {
        let firstPhoneID = first(of: .phone)?.id
        let extras = phones.map { ContactEntry(id: $0.id, kind: .phone, label: $0.label, value: $0.value, privacy: privacy ?? $0.privacy) }
        removeAll { $0.kind == .phone && $0.id != firstPhoneID }
        let insertAt = firstIndex { $0.id == firstPhoneID }.map { $0 + 1 } ?? endIndex
        insert(contentsOf: extras, at: insertAt)
    }

    /// Without what the legacy fields express: every phone and the first email, telegram, website, linkedin.
    func droppingLegacyExpressible() -> [ContactEntry] {
        var firstTaken = Set<ContactFieldKind>()
        return filter { entry in
            guard !entry.isEmpty else { return false }
            if entry.kind == .phone { return false }
            guard entry.kind.isLegacy else { return true }
            return !firstTaken.insert(entry.kind).inserted
        }
    }

    /// Appends someone's entries that are not here yet (same kind and `matchKey`), as Connections-level,
    /// while there is room. Phones take a fresh id when theirs is already used.
    /// - Parameter adoptsLabels: a number already here takes the incoming entry's label — its owner knows
    ///   whether it's Mobile or Work (off when merging two of your own records).
    /// - Returns: whether anything changed.
    @discardableResult
    mutating func merge(_ incoming: [ContactEntry], adoptsLabels: Bool = false) -> Bool {
        var known = Set(filter { !$0.isEmpty }.map { "\($0.kind.rawValue):\($0.matchKey)" })
        var ids = Set(map(\.id))
        var changed = false
        if adoptsLabels {
            for entry in incoming where entry.kind == .phone && !entry.matchKey.isEmpty {
                if let index = firstIndex(where: { $0.kind == .phone && $0.matchKey == entry.matchKey }), self[index].label != entry.label {
                    self[index].label = entry.label
                    changed = true
                }
            }
        }
        for var entry in incoming where !entry.isEmpty && !entry.matchKey.isEmpty {
            guard filter({ !$0.isEmpty }).count < ContactEntry.maxCount else { break }
            guard known.insert("\(entry.kind.rawValue):\(entry.matchKey)").inserted else { continue }
            if !ids.insert(entry.id).inserted {
                entry.id = UUID()
                ids.insert(entry.id)
            }
            entry.value = String(entry.value.trimmingCharacters(in: .whitespaces).prefix(ContactEntry.maxLength(for: entry.kind)))
            entry.privacy = .connections
            append(entry)
            changed = true
        }
        return changed
    }
}

/// Everything about how a card looks. Stored on `Card` and sent to the server as-is.
public struct CardDesign: Codable, Hashable, Sendable {
    public var template: CardTemplate
    public var palette: CardPalette
    public var appearance: CardAppearance
    public var font: CardFont
    public var alignment: CardAlignment
    public var density: CardDensity
    public var background: CardBackground
    public var showQR: Bool
    public var showPhoto: Bool
    public var showLogo: Bool
    public var visibleFields: Set<ContactFieldKind>

    public init(
        template: CardTemplate = .minimal,
        palette: CardPalette = .ink,
        appearance: CardAppearance = .dark,
        font: CardFont = .system,
        alignment: CardAlignment = .leading,
        density: CardDensity = .balanced,
        background: CardBackground = .solid,
        showQR: Bool = true,
        showPhoto: Bool = true,
        showLogo: Bool = true,
        visibleFields: Set<ContactFieldKind> = [.phone, .email, .telegram, .website]
    ) {
        self.template = template
        self.palette = palette
        self.appearance = appearance
        self.font = font
        self.alignment = alignment
        self.density = density
        self.background = background
        self.showQR = showQR
        self.showPhoto = showPhoto
        self.showLogo = showLogo
        self.visibleFields = visibleFields
    }

    public var usesProFeatures: Bool { template.isPro || palette.isPro }
}

/// The values rendered on a card face, already filtered for the audience.
/// Built by MetlyData (`Card.faceContent(profile:audience:)`) and consumed by MetlyCardKit.
public struct CardFaceContent: Hashable, Sendable {
    public var fullName: String
    public var jobTitle: String
    public var company: String
    public var photoData: Data?
    public var logoData: Data?
    /// Every entry the card shows to this audience, in the owner's order (3.0.0) — the only stored form;
    /// `fields` / `additionalPhones` / `phoneLabel` are one-per-kind views of it.
    public var contacts: [ContactEntry]
    /// True when `contacts` is already the card's selection (built from a 3.0.0 profile). False for content
    /// built from one-per-kind fields (someone's card snapshot, older callers): renderers then still
    /// apply `design.visibleFields`, as before 3.0.0.
    public var isSelection: Bool
    /// What the QR encodes (card URL, or a vCard string for offline QR).
    public var qrPayload: String

    public init(fullName: String, jobTitle: String = "", company: String = "", photoData: Data? = nil,
                logoData: Data? = nil, fields: [ContactField] = [], qrPayload: String = "",
                additionalPhones: [LabeledPhone] = [], phoneLabel: PhoneLabel = .mobile, contacts: [ContactEntry]? = nil) {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.photoData = photoData
        self.logoData = logoData
        self.contacts = contacts ?? .fromLegacy(fields: fields, phoneLabel: phoneLabel, additionalPhones: additionalPhones,
                                                keeping: fields.filter { !$0.kind.isLegacy }.map {
                                                    ContactEntry(kind: $0.kind, value: $0.value, privacy: $0.privacy)
                                                })
        self.isSelection = contacts != nil
        self.qrPayload = qrPayload
    }

    /// The first entry of each kind (display order of the kinds).
    public var fields: [ContactField] {
        get { ContactFieldKind.allCases.compactMap { contacts.first(of: $0)?.field } }
        set {
            contacts = .fromLegacy(fields: newValue, phoneLabel: phoneLabel, additionalPhones: additionalPhones,
                                   keeping: newValue.filter { !$0.kind.isLegacy }.map {
                                       ContactEntry(kind: $0.kind, value: $0.value, privacy: $0.privacy)
                                   })
        }
    }

    /// The phones after the first one.
    public var additionalPhones: [LabeledPhone] {
        get { Array(contacts.entries(of: .phone).dropFirst().map(\.labeledPhone)) }
        set { contacts.setExtraPhones(newValue) }
    }

    /// Label of the first phone.
    public var phoneLabel: PhoneLabel {
        get { contacts.legacyPhoneLabel }
        set { contacts.setFirstPhoneLabel(newValue) }
    }

    public var role: String { [jobTitle, company].filter { !$0.isEmpty }.joined(separator: " · ") }

    public var initials: String {
        fullName.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    public var firstName: String { fullName.split(separator: " ").first.map(String.init) ?? fullName }
}

/// A frozen copy of someone else's card (as shared with the owner).
public struct CardSnapshot: Codable, Hashable, Sendable {
    public var cardName: String
    public var design: CardDesign
    public var fullName: String
    public var jobTitle: String
    public var company: String
    public var fields: [ContactField]
    public var url: URL?

    public init(cardName: String, design: CardDesign, fullName: String, jobTitle: String = "",
                company: String = "", fields: [ContactField] = [], url: URL? = nil) {
        self.cardName = cardName
        self.design = design
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.fields = fields
        self.url = url
    }

    public var faceContent: CardFaceContent {
        CardFaceContent(fullName: fullName, jobTitle: jobTitle, company: company,
                        fields: fields.filter { !$0.isEmpty }, qrPayload: url?.absoluteString ?? "")
    }
}

/// "Where you met" — auto-filled at capture time.
public struct MeetingContext: Codable, Hashable, Sendable {
    public var eventID: UUID?
    public var eventName: String?
    public var place: String?
    public var city: String?
    public var metAt: Date

    public init(eventID: UUID? = nil, eventName: String? = nil, place: String? = nil, city: String? = nil, metAt: Date = .now) {
        self.eventID = eventID
        self.eventName = eventName
        self.place = place
        self.city = city
        self.metAt = metAt
    }
}

public struct CardStats: Codable, Hashable, Sendable {
    public var views: Int
    public var saves: Int
    public var shareBacks: Int
    public var scans: Int

    public init(views: Int = 0, saves: Int = 0, shareBacks: Int = 0, scans: Int = 0) {
        self.views = views
        self.saves = saves
        self.shareBacks = shareBacks
        self.scans = scans
    }
}

public struct NotificationPrefs: Codable, Hashable, Sendable {
    public var followUpReminders = true
    public var eventSummary = true
    /// Retired with the Telegram reminders bot: reminders are always push. Kept only because this struct
    /// is stored in the frozen SwiftData schema versions; nothing reads it and the server ignores it.
    public var delivery: ReminderDelivery = .push
    /// Retired with the Telegram reminders bot (see `delivery`).
    public var telegramLinked = false
    public var connectRequests = true
    public var cardSaved = true
    public var weeklySummary = false
    public var productNews = false
    public init() {}

    // Tolerant decoding: keys added later fall back to defaults (older payloads keep decoding).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = NotificationPrefs.defaults
        followUpReminders = try c.decodeIfPresent(Bool.self, forKey: .followUpReminders) ?? d.followUpReminders
        eventSummary = try c.decodeIfPresent(Bool.self, forKey: .eventSummary) ?? d.eventSummary
        delivery = try c.decodeIfPresent(ReminderDelivery.self, forKey: .delivery) ?? d.delivery
        telegramLinked = try c.decodeIfPresent(Bool.self, forKey: .telegramLinked) ?? d.telegramLinked
        connectRequests = try c.decodeIfPresent(Bool.self, forKey: .connectRequests) ?? d.connectRequests
        cardSaved = try c.decodeIfPresent(Bool.self, forKey: .cardSaved) ?? d.cardSaved
        weeklySummary = try c.decodeIfPresent(Bool.self, forKey: .weeklySummary) ?? d.weeklySummary
        productNews = try c.decodeIfPresent(Bool.self, forKey: .productNews) ?? d.productNews
    }

    private static let defaults = NotificationPrefs()
}

public struct PrivacySettings: Codable, Hashable, Sendable {
    public var findByEmail = true
    public var showInNearby = true
    public var shareAnalytics = true
    public init() {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        findByEmail = try c.decodeIfPresent(Bool.self, forKey: .findByEmail) ?? true
        showInNearby = try c.decodeIfPresent(Bool.self, forKey: .showInNearby) ?? true
        shareAnalytics = try c.decodeIfPresent(Bool.self, forKey: .shareAnalytics) ?? true
    }
}

/// Result of resolving a deferred deep link on first launch (DEFERRED_WELCOME).
public struct DeferredInvite: Hashable, Sendable {
    public var ownerName: String
    public var ownerTitle: String
    public var eventName: String?
    public var card: CardSnapshot
    public var cardSlug: String

    public init(ownerName: String, ownerTitle: String, eventName: String?, card: CardSnapshot, cardSlug: String) {
        self.ownerName = ownerName
        self.ownerTitle = ownerTitle
        self.eventName = eventName
        self.card = card
        self.cardSlug = cardSlug
    }
}
