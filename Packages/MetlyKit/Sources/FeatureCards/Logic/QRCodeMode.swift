import Foundation
import MetlyCore

/// What QR_FULLSCREEN encodes (SPEC §3.7): the card link, or — for "Offline QR" — a vCard with the
/// public contact details only (no analytics, no Connect). A card without a slug can only show the vCard.
nonisolated enum QRCodeMode: Equatable, Sendable {
    case link(URL)
    case contact(vCard: String)

    var payload: String {
        switch self {
        case .link(let url): url.absoluteString
        case .contact(let vCard): vCard
        }
    }

    var isOffline: Bool {
        if case .contact = self { return true }
        return false
    }

    /// - Parameters:
    ///   - prefersOffline: the Offline QR switch (nil = automatic).
    ///   - publicContent: `.public` audience content (the vCard can leave the device).
    static func resolve(url: URL?, isOnline: Bool, prefersOffline: Bool?, publicContent: CardFaceContent) -> QRCodeMode {
        let offline = prefersOffline ?? defaultsToOffline(url: url, isOnline: isOnline)
        if let url, !offline { return .link(url) }
        return .contact(vCard: CardContentFactory.vCard(for: publicContent, url: url))
    }

    /// Offline QR switches itself on when there is no network or no published link yet.
    static func defaultsToOffline(url: URL?, isOnline: Bool) -> Bool {
        url == nil || !isOnline
    }
}
