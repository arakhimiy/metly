import Foundation

// Domain enums shared by SwiftData models, DTOs and UI.
// Raw values are the wire format agreed in docs/api/openapi.yaml — do not rename cases.

public enum ContactFieldKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case phone, email, telegram, website, linkedin   // the original five (wire `contactFields` / `visibleFields`)
    case whatsapp, instagram, address                 // contact list only (schema 3.0.0, docs/api/CONTACTS.md)

    public var id: String { rawValue }

    /// Kinds the legacy wire fields (`contactFields`, `visibleFields`, `CardSnapshot.fields`) can carry;
    /// older apps fail to decode anything else there.
    public static let legacy: [ContactFieldKind] = [.phone, .email, .telegram, .website, .linkedin]
    public var isLegacy: Bool { Self.legacy.contains(self) }

    /// Order of the kinds in "+ Add Contact".
    public static let addOrder: [ContactFieldKind] = [.phone, .telegram, .whatsapp, .instagram, .email, .website, .linkedin, .address]

    public var title: String {
        switch self {
        case .phone: String(localized: "Phone", bundle: .appStrings)
        case .email: String(localized: "Email", bundle: .appStrings)
        case .telegram: String(localized: "Telegram", bundle: .appStrings)
        case .website: String(localized: "Website", bundle: .appStrings)
        case .linkedin: String(localized: "LinkedIn", bundle: .appStrings)
        case .whatsapp: String(localized: "WhatsApp", bundle: .appStrings)
        case .instagram: String(localized: "Instagram", bundle: .appStrings)
        case .address: String(localized: "Address", bundle: .appStrings)
        }
    }

    /// SF Symbol used in lists and card faces.
    public var symbolName: String {
        switch self {
        case .phone: "phone.fill"
        case .email: "envelope.fill"
        case .telegram: "paperplane.fill"
        case .website: "globe"
        case .linkedin: "person.crop.square.filled.and.at.rectangle"
        case .whatsapp: "message.fill"
        case .instagram: "camera.fill"
        case .address: "mappin.and.ellipse"
        }
    }

    public var defaultPrivacy: FieldPrivacy {
        switch self {
        case .phone, .linkedin, .whatsapp: .connections
        case .email, .telegram, .website, .instagram, .address: .public
        }
    }

    /// Values are phone numbers (digits compare equal, `tel:`-style keyboard and limits).
    public var isPhoneNumber: Bool { self == .phone || self == .whatsapp }
}

/// Label of a phone number (vCard TEL;TYPE). Added in schema 2.0.0.
public enum PhoneLabel: String, Codable, CaseIterable, Sendable, Identifiable {
    case mobile, work, home, other

    public var id: String { rawValue }

    public var title: String {
        switch self {
        // Own keys: "Home"/"Work" already mean the tab and the card name in the catalog.
        case .mobile: String(localized: "phoneLabel.mobile", defaultValue: "Mobile", bundle: .appStrings)
        case .work: String(localized: "phoneLabel.work", defaultValue: "Work", bundle: .appStrings)
        case .home: String(localized: "phoneLabel.home", defaultValue: "Home", bundle: .appStrings)
        case .other: String(localized: "phoneLabel.other", defaultValue: "Other", bundle: .appStrings)
        }
    }

    public var symbolName: String {
        switch self {
        case .mobile: "iphone"
        case .work: "building.2"
        case .home: "house"
        case .other: "phone"
        }
    }
}

public enum FieldPrivacy: String, Codable, CaseIterable, Sendable, Identifiable {
    case `public`, connections, `private`

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .public: String(localized: "Public", bundle: .appStrings, comment: "Field privacy level")
        case .connections: String(localized: "Connections", bundle: .appStrings, comment: "Field privacy level: visible to people you've connected with")
        case .private: String(localized: "Private", bundle: .appStrings, comment: "Field privacy level")
        }
    }

    public var explanation: String {
        switch self {
        case .public: String(localized: "Anyone with your link", bundle: .appStrings)
        case .connections: String(localized: "People you’ve connected with", bundle: .appStrings)
        case .private: String(localized: "Only you", bundle: .appStrings)
        }
    }
}

/// Who is looking at a card face — decides which fields are rendered.
public enum CardAudience: Sendable {
    /// In-app previews for the owner or an accepted connection: Public + Connections.
    case connections
    /// Anything that can leave the device (web page, exports, Wallet, Lock Screen): Public only.
    case `public`

    public func allows(_ privacy: FieldPrivacy) -> Bool {
        switch (self, privacy) {
        case (_, .private): false
        case (.connections, _): true
        case (.public, .public): true
        case (.public, _): false
        }
    }
}

public enum CardTemplate: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal, professional, modern, bold, gradient, split, terminal, stack, editorial
    public var id: String { rawValue }
    /// Design name, kept in English on purpose (like a font name). The wire ids stay as they were in 1.0 so
    /// older apps keep decoding cards; only the look and the name changed in v2 (docs/design/card-templates-v2.md).
    public var title: String {
        switch self {
        case .minimal: "Classic"
        case .professional: "Monogram"
        case .modern: "Foil"
        case .bold: "Wordmark"
        case .gradient: "Aurora"
        case .split: "Duotone"
        case .terminal: "Terminal"
        case .stack: "Centered"
        case .editorial: "Editorial"
        }
    }
    /// The finish templates (foil, gradient, metal) are Pro. Server mirror: `PRO_TEMPLATES` in wire.ts.
    public var isPro: Bool { [.modern, .gradient, .editorial].contains(self) }

    /// Picker order: free templates first, then Pro.
    public static var pickerOrder: [CardTemplate] {
        [.minimal, .professional, .bold, .split, .stack, .terminal, .modern, .gradient, .editorial]
    }
}

/// How a card draws the owner's logo: as uploaded, or one-colour in the template's ink (foil, deboss…).
public enum CardLogoStyle: String, Codable, CaseIterable, Sendable {
    case original, mono
}

public enum CardPalette: String, Codable, CaseIterable, Sendable, Identifiable {
    case graphite, snow, ink, sand, ocean, ember
    public var id: String { rawValue }
    /// Design name, kept in English on purpose (like a font name).
    public var title: String { rawValue.capitalized }
    public var isPro: Bool { self == .ocean || self == .ember }
}

public enum CardAppearance: String, Codable, CaseIterable, Sendable { case light, dark }

public enum CardFont: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, rounded, serif, mono
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: String(localized: "Default", bundle: .appStrings, comment: "Badge of the default card; also the system card typeface")
        case .rounded: String(localized: "Rounded", bundle: .appStrings, comment: "Card typeface; also the rounded-corners image export style")
        case .serif: String(localized: "Serif", bundle: .appStrings)
        case .mono: String(localized: "Mono", bundle: .appStrings)
        }
    }
}

public enum CardAlignment: String, Codable, CaseIterable, Sendable { case leading, center }

public enum CardDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal, balanced, detailed
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .minimal: String(localized: "Minimal", bundle: .appStrings, comment: "Card density: fewest contact rows")
        case .balanced: String(localized: "Balanced", bundle: .appStrings, comment: "Card density")
        case .detailed: String(localized: "Detailed", bundle: .appStrings, comment: "Card density: most contact rows")
        }
    }
    /// Maximum number of contact rows rendered on the face.
    public var maxContacts: Int {
        switch self {
        case .minimal: 2
        case .balanced: 3
        case .detailed: 5
        }
    }
}

public enum CardBackground: String, Codable, CaseIterable, Sendable { case solid, gradient }

public enum CardPublishState: String, Codable, Sendable { case draft, published }

public enum ConnectionSource: String, Codable, CaseIterable, Sendable {
    case nearby, tapPhones, scanQR, justMet, webShareBack, paper, contactsCapture, connectRequest, deferredLink, manual

    /// Short meta label shown in People rows ("via web", "via QR"…), nil when not shown.
    public var viaLabel: String? {
        switch self {
        case .webShareBack: String(localized: "via web", bundle: .appStrings)
        case .justMet, .scanQR: String(localized: "via QR", bundle: .appStrings)
        case .paper: String(localized: "via paper card", bundle: .appStrings)
        case .nearby: String(localized: "via Nearby", bundle: .appStrings)
        case .tapPhones: String(localized: "via Tap", bundle: .appStrings)
        default: nil
        }
    }
}

public enum FollowUpChannel: String, Codable, CaseIterable, Sendable, Identifiable {
    case telegram, email, call
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .telegram: String(localized: "Telegram", bundle: .appStrings)
        case .email: String(localized: "Email", bundle: .appStrings)
        case .call: String(localized: "Call", bundle: .appStrings, comment: "Phone call: button and follow-up channel")
        }
    }
    public var symbolName: String {
        switch self {
        case .telegram: "paperplane.fill"
        case .email: "envelope.fill"
        case .call: "phone.fill"
        }
    }
}

public enum ConnectRequestStatus: String, Codable, Sendable { case pending, accepted, declined, expired, cancelled }
public enum ConnectRequestDirection: String, Codable, Sendable { case incoming, outgoing }
public enum ConnectMethod: String, Codable, Sendable { case nearby, tapPhones, scan, emailLookup, deferred }

public enum EventStatus: String, Codable, Sendable { case active, ended }

public enum Plan: String, Codable, Sendable { case free, pro }

/// Retired (Telegram reminders bot removed); kept for the stored `NotificationPrefs` shape only.
public enum ReminderDelivery: String, Codable, CaseIterable, Sendable { case push, telegramBot }

public enum AppAppearance: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: String(localized: "System", bundle: .appStrings, comment: "App appearance: follow the iOS setting")
        case .light: String(localized: "Light", bundle: .appStrings, comment: "Appearance: app or card")
        case .dark: String(localized: "Dark", bundle: .appStrings, comment: "Appearance: app or card")
        }
    }
}

/// Local sync bookkeeping for every SwiftData record.
public enum SyncState: String, Codable, Sendable {
    case synced
    case pendingUpsert
    case pendingDelete
}
