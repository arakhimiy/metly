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

    /// The Offline QR switch after the device went online / offline. Losing the network overrides an
    /// explicit "show the link" choice by going back to automatic (→ vCard now, the link again once
    /// online). Automatic stays automatic, and an explicit Offline QR choice is kept.
    static func preference(afterConnectivityChange current: Bool?, isOnline: Bool) -> Bool? {
        if !isOnline, current == false { return nil }
        return current
    }

    /// Offline QR switches itself on when there is no network or no published link yet.
    static func defaultsToOffline(url: URL?, isOnline: Bool) -> Bool {
        url == nil || !isOnline
    }
}

/// QR_FULLSCREEN card chooser: the selected card, or the first one once it is gone.
nonisolated enum QRCardSelection {
    static func resolve(_ selected: UUID, among ids: [UUID]) -> UUID? {
        ids.contains(selected) ? selected : ids.first
    }
}
