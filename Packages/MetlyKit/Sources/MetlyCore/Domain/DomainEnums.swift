import Foundation

// Domain enums shared by SwiftData models, DTOs and UI.
// Raw values are the wire format agreed in docs/api/openapi.yaml — do not rename cases.

public enum ContactFieldKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case phone, email, telegram, website, linkedin   // fixed display order

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .phone: "Phone"
        case .email: "Email"
        case .telegram: "Telegram"
        case .website: "Website"
        case .linkedin: "LinkedIn"
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
        }
    }

    public var defaultPrivacy: FieldPrivacy {
        switch self {
        case .phone, .linkedin: .connections
        case .email, .telegram, .website: .public
        }
    }
}

public enum FieldPrivacy: String, Codable, CaseIterable, Sendable, Identifiable {
    case `public`, connections, `private`

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .public: "Public"
        case .connections: "Connections"
        case .private: "Private"
        }
    }

    public var explanation: String {
        switch self {
        case .public: "Anyone with your link"
        case .connections: "People you've connected with"
        case .private: "Only you"
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
    public var title: String { rawValue.capitalized }
    public var isPro: Bool { self == .editorial }
}

public enum CardPalette: String, Codable, CaseIterable, Sendable, Identifiable {
    case graphite, snow, ink, sand, ocean, ember
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
    public var isPro: Bool { self == .ocean || self == .ember }
}

public enum CardAppearance: String, Codable, CaseIterable, Sendable { case light, dark }

public enum CardFont: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, rounded, serif, mono
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .system: "Default"
        case .rounded: "Rounded"
        case .serif: "Serif"
        case .mono: "Mono"
        }
    }
}

public enum CardAlignment: String, Codable, CaseIterable, Sendable { case leading, center }

public enum CardDensity: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal, balanced, detailed
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
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
        case .webShareBack: "via web"
        case .justMet, .scanQR: "via QR"
        case .paper: "via paper card"
        case .nearby: "via Nearby"
        case .tapPhones: "via Tap"
        default: nil
        }
    }
}

public enum FollowUpChannel: String, Codable, CaseIterable, Sendable, Identifiable {
    case telegram, email, call
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .telegram: "Telegram"
        case .email: "Email"
        case .call: "Call"
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

public enum ReminderDelivery: String, Codable, CaseIterable, Sendable { case push, telegramBot }

public enum AppAppearance: String, Codable, CaseIterable, Sendable, Identifiable {
    case system, light, dark
    public var id: String { rawValue }
    public var title: String { rawValue.capitalized }
}

/// Local sync bookkeeping for every SwiftData record.
public enum SyncState: String, Codable, Sendable {
    case synced
    case pendingUpsert
    case pendingDelete
}
