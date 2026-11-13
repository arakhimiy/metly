import Foundation

/// Card options for widget configuration and the "Show My QR" Shortcuts parameter.
/// `AppEntity` wrappers live in the extension / app targets (App Intents metadata must be extracted
/// from the target that declares them); this type holds the shared logic.
nonisolated public struct WidgetCardChoice: Hashable, Sendable, Identifiable {
    /// Follows the card to share: the default card, or the active event's card.
    public static let automaticID = "automatic"

    public let id: String
    public let title: String
    public let subtitle: String

    public init(id: String, title: String, subtitle: String) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
    }

    /// The concrete card, nil for "Card to Share".
    public var cardID: UUID? { UUID(uuidString: id) }

    public static var automatic: WidgetCardChoice {
        WidgetCardChoice(id: automaticID, title: String(localized: "Card to Share", bundle: .appStrings),
                         subtitle: String(localized: "Your default card, or your event’s card", bundle: .appStrings))
    }

    /// "Card to Share" first, then every card.
    public static func all(in snapshot: WidgetSnapshot?) -> [WidgetCardChoice] {
        [automatic] + (snapshot?.cards ?? []).map(choice(for:))
    }

    /// Resolves stored ids; ids of deleted cards are omitted (App Intents expects that).
    public static func choices(for ids: [String], in snapshot: WidgetSnapshot?) -> [WidgetCardChoice] {
        let available = all(in: snapshot)
        return ids.compactMap { id in available.first { $0.id == id } }
    }

    public static func matching(_ text: String, in snapshot: WidgetSnapshot?) -> [WidgetCardChoice] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all(in: snapshot) }
        return all(in: snapshot).filter { $0.title.localizedStandardContains(query) }
    }

    static func choice(for card: WidgetCard) -> WidgetCardChoice {
        let subtitle: String
        if card.isDefault {
            subtitle = String(localized: "Default card", bundle: .appStrings)
        } else if let url = card.url, let host = url.host() {
            subtitle = host + url.path()
        } else {
            subtitle = String(localized: "Not published yet", bundle: .appStrings)
        }
        return WidgetCardChoice(id: card.id.uuidString, title: card.displayName, subtitle: subtitle)
    }
}
