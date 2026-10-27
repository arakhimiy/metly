import Foundation
import MetlyCore

/// Whether a card's public link exists yet. Cards get their slug from the server on first sync;
/// until then link actions are disabled (the offline QR still works).
nonisolated enum CardLinkStatus: Equatable, Sendable {
    case live(URL)
    /// Online, waiting for the server to assign the slug.
    case publishing
    /// Offline draft; publishes when the device is back online.
    case waitingForNetwork

    init(url: URL?, isOnline: Bool) {
        if let url {
            self = .live(url)
        } else {
            self = isOnline ? .publishing : .waitingForNetwork
        }
    }

    var url: URL? {
        if case .live(let url) = self { return url }
        return nil
    }

    /// "tanishly.app/c/aziza-w7k2" / "Publishing…" / "Not published yet".
    var displayText: String {
        switch self {
        case .live(let url): Self.shortText(for: url)
        case .publishing: String(localized: "Publishing…")
        case .waitingForNetwork: String(localized: "Not published yet")
        }
    }

    /// Footer copy explaining a missing link (nil when live).
    var explanation: String? {
        switch self {
        case .live: nil
        case .publishing: String(localized: "Your link appears in a moment, as soon as the card is published.")
        case .waitingForNetwork: String(localized: "Your card is saved as a draft and will publish when you’re back online.")
        }
    }

    /// Link without the scheme, as shown in the UI.
    static func shortText(for url: URL) -> String {
        let text = url.absoluteString
        for prefix in ["https://", "http://"] where text.hasPrefix(prefix) {
            return String(text.dropFirst(prefix.count))
        }
        return text
    }
}
