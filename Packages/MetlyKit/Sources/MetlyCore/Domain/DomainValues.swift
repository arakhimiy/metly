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
    /// Non-empty, audience-allowed, design-visible fields in display order (density is applied by the renderer).
    public var fields: [ContactField]
    /// What the QR encodes (card URL, or a vCard string for offline QR).
    public var qrPayload: String

    public init(fullName: String, jobTitle: String = "", company: String = "", photoData: Data? = nil,
                logoData: Data? = nil, fields: [ContactField] = [], qrPayload: String = "") {
        self.fullName = fullName
        self.jobTitle = jobTitle
        self.company = company
        self.photoData = photoData
        self.logoData = logoData
        self.fields = fields
        self.qrPayload = qrPayload
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
    public var delivery: ReminderDelivery = .push
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
