import Foundation
import MetlyCore

/// Everything the widget extension shows, written by the app into the App Group container
/// (the extension never opens the SwiftData store).
///
/// Privacy (SPEC §9 Q4): card faces and QR payloads carry **Public** fields only — widgets can sit on
/// the Lock Screen. Follow-up rows carry the person's name and the reminder text; the views mark
/// them `privacySensitive()`.
///
/// Counts are stored as raw dates so every timeline entry can re-evaluate "due today" and
/// "this week" at its own date (an entry rendered after midnight must not show yesterday's numbers).
nonisolated public struct WidgetSnapshot: Codable, Hashable, Sendable {
    /// Bump when the JSON shape changes incompatibly; older files are then ignored until the app rewrites them.
    public static let currentSchemaVersion = 1
    /// Detailed follow-up rows kept in the snapshot (the widget shows at most 3, the rest
    /// cover "Done" taps and midnight roll-over without waiting for the app).
    public static let maxFollowUps = 10
    /// Connections older than this never count as "this week".
    public static let recentConnectionWindow: TimeInterval = 8 * 24 * 60 * 60

    public var schemaVersion: Int
    public var generatedAt: Date
    /// nil = signed out (or setup not finished): widgets show "Open Tanishly".
    public var owner: WidgetOwner?
    /// Every live card, in the user's order.
    public var cards: [WidgetCard]
    /// The card to share right now: the active event's card, else the default card.
    public var shareCardID: UUID?
    /// Earliest open follow-ups, sorted by due date (≤ `maxFollowUps`).
    public var followUps: [WidgetFollowUp]
    /// Due date of every open follow-up, ascending (drives the counts).
    public var openFollowUpDueDates: [Date]
    /// Creation dates of connections made in the last 8 days, newest first.
    public var recentConnectionDates: [Date]
    public var activeEventName: String?

    public init(generatedAt: Date = .now, owner: WidgetOwner?, cards: [WidgetCard] = [], shareCardID: UUID? = nil,
                followUps: [WidgetFollowUp] = [], openFollowUpDueDates: [Date] = [], recentConnectionDates: [Date] = [],
                activeEventName: String? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.generatedAt = generatedAt
        self.owner = owner
        self.cards = cards
        self.shareCardID = shareCardID
        self.followUps = followUps
        self.openFollowUpDueDates = openFollowUpDueDates
        self.recentConnectionDates = recentConnectionDates
        self.activeEventName = activeEventName
    }

    /// What widgets show after sign-out: nothing personal.
    public static func signedOut(at date: Date = .now) -> WidgetSnapshot {
        WidgetSnapshot(generatedAt: date, owner: nil)
    }

    public var isSignedIn: Bool { owner != nil }

    // MARK: Cards

    public func card(id: UUID) -> WidgetCard? {
        cards.first { $0.id == id }
    }

    /// The card to share now (falls back to the first card when the stored id went stale).
    public var shareCard: WidgetCard? {
        shareCardID.flatMap(card(id:)) ?? cards.first(where: \.isDefault) ?? cards.first
    }

    /// A widget's configured card, or the card to share when it is automatic or no longer exists.
    public func resolveCard(id: UUID?) -> WidgetCard? {
        id.flatMap(card(id:)) ?? shareCard
    }

    // MARK: Follow-ups

    public var openFollowUpCount: Int { openFollowUpDueDates.count }

    /// Open follow-ups due today or earlier (overdue) at `date`.
    public func dueFollowUpCount(at date: Date, calendar: Calendar = .current) -> Int {
        let endOfDay = Self.startOfNextDay(after: date, calendar: calendar)
        return openFollowUpDueDates.count { $0 < endOfDay }
    }

    /// Detailed due/overdue rows at `date`, earliest first.
    public func dueFollowUps(at date: Date, calendar: Calendar = .current) -> [WidgetFollowUp] {
        let endOfDay = Self.startOfNextDay(after: date, calendar: calendar)
        return followUps.filter { $0.dueAt < endOfDay }
    }

    /// The first follow-up that is not due yet at `date` ("Next: …" in the empty state).
    public func nextFollowUp(after date: Date, calendar: Calendar = .current) -> WidgetFollowUp? {
        let endOfDay = Self.startOfNextDay(after: date, calendar: calendar)
        return followUps.first { $0.dueAt >= endOfDay }
    }

    // MARK: Connections

    /// Connections created in the calendar week that contains `date`.
    public func newConnectionsThisWeek(at date: Date, calendar: Calendar = .current) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return recentConnectionDates.count { week.start <= $0 && $0 <= date }
    }

    static func startOfNextDay(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Same content regardless of when it was generated (change detection before reloading widgets).
    func hasSameContent(as other: WidgetSnapshot) -> Bool {
        var lhs = self, rhs = other
        lhs.generatedAt = .distantPast
        rhs.generatedAt = .distantPast
        return lhs == rhs
    }
}

/// The signed-in user as shown on widgets (name, role, card media thumbnails, pause state).
nonisolated public struct WidgetOwner: Codable, Hashable, Sendable {
    public var fullName: String
    public var jobTitle: String
    public var company: String
    /// Downscaled profile photo, only when a card template renders it.
    public var photoThumbnail: Data?
    /// Downscaled logo, only when a card template renders it.
    public var logoThumbnail: Data?
    /// "Pause All Links": QR links show an inactive page.
    public var linksPaused: Bool

    public init(fullName: String, jobTitle: String = "", company: String = "", photoThumbnail: Data? = nil,
                logoThumbnail: Data? = nil, linksPaused: Bool = false) {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.photoThumbnail = photoThumbnail
        self.logoThumbnail = logoThumbnail
        self.linksPaused = linksPaused
    }

    public var displayName: String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? Brand.appName : trimmed
    }

    public var firstName: String {
        displayName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? displayName
    }

    public var role: String {
        [jobTitle, company].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// One of the owner's cards with its **public** face data.
nonisolated public struct WidgetCard: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var design: CardDesign
    /// `https://tanishly.app/c/{slug}`; nil until the card is published.
    public var url: URL?
    /// Public, design-visible, non-empty fields in display order.
    public var fields: [ContactField]
    /// The card link, or an offline vCard (public fields only) while the card has no link.
    public var qrPayload: String
    public var isDefault: Bool
    /// Public extra phone numbers (empty when the card hides phones).
    public var additionalPhones: [LabeledPhone]
    /// Label of the primary phone in `fields`.
    public var phoneLabel: PhoneLabel
    /// The card's Public entries in the owner's order (3.0.0); nil in snapshots written before.
    public var contacts: [ContactEntry]?

    public init(id: UUID, name: String, design: CardDesign, url: URL?, fields: [ContactField], qrPayload: String,
                isDefault: Bool = false, additionalPhones: [LabeledPhone] = [], phoneLabel: PhoneLabel = .mobile,
                contacts: [ContactEntry]? = nil) {
        self.id = id
        self.name = name
        self.design = design
        self.url = url
        self.fields = fields
        self.qrPayload = qrPayload
        self.isDefault = isDefault
        self.additionalPhones = additionalPhones
        self.phoneLabel = phoneLabel
        self.contacts = contacts
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, design, url, fields, qrPayload, isDefault, additionalPhones, phoneLabel, contacts
    }

    /// Snapshots written before labelled phones (no `additionalPhones` / `phoneLabel`) still decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        design = try container.decode(CardDesign.self, forKey: .design)
        url = try container.decodeIfPresent(URL.self, forKey: .url)
        fields = try container.decode([ContactField].self, forKey: .fields)
        qrPayload = try container.decode(String.self, forKey: .qrPayload)
        isDefault = try container.decode(Bool.self, forKey: .isDefault)
        additionalPhones = try container.decodeIfPresent([LabeledPhone].self, forKey: .additionalPhones) ?? []
        phoneLabel = try container.decodeIfPresent(PhoneLabel.self, forKey: .phoneLabel) ?? .mobile
        contacts = try? container.decodeIfPresent([ContactEntry].self, forKey: .contacts)
    }

    /// "{Card} Card" (SPEC §2.5.16), without doubling a name that already ends in "Card".
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return String(localized: "Card") }
        return trimmed.lowercased().hasSuffix("card") ? trimmed : String(localized: "\(trimmed) Card")
    }

    /// The QR encodes contact details instead of a link (card not published yet).
    public var usesOfflineQR: Bool { url == nil }

    /// Values for `CardFaceView` (Public audience).
    public func faceContent(owner: WidgetOwner) -> CardFaceContent {
        CardFaceContent(fullName: owner.fullName, jobTitle: owner.jobTitle, company: owner.company,
                        photoData: owner.photoThumbnail, logoData: owner.logoThumbnail,
                        fields: fields, qrPayload: qrPayload, additionalPhones: additionalPhones, phoneLabel: phoneLabel,
                        contacts: contacts)
    }

    /// The design the widget renders: always with its QR (the widget exists to be scanned).
    public var widgetDesign: CardDesign {
        var copy = design
        copy.showQR = true
        return copy
    }
}

/// An open reminder row.
nonisolated public struct WidgetFollowUp: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// What to do ("Send the deck").
    public var title: String
    public var personName: String
    public var connectionID: UUID?
    /// "{event or company}" — second part of "{name} · {event or company}".
    public var context: String?
    public var dueAt: Date
    public var channel: FollowUpChannel

    public init(id: UUID, title: String, personName: String, connectionID: UUID? = nil, context: String? = nil,
                dueAt: Date, channel: FollowUpChannel) {
        self.id = id
        self.title = title
        self.personName = personName
        self.connectionID = connectionID
        self.context = context
        self.dueAt = dueAt
        self.channel = channel
    }
}
