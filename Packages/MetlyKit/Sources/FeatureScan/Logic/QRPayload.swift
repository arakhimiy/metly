import Foundation

/// What a scanned QR code (or pasted text) contains — decides where SCAN goes next.
nonisolated enum QRPayload: Equatable, Sendable {
    /// Someone's Metly card link → SCANNED_CARD.
    case metlyCard(url: URL, slug: String)
    /// One of the owner's own cards → "That's your card" toast.
    case ownCard(slug: String)
    /// A foreign contact card (vCard text; a MECARD arrives converted to vCard) → SCANNED_CARD
    /// contact review (SPEC §9 Q41).
    case vCard(String)
    /// Any other web link → ALERT_INVALID_QR with "Open in Safari".
    case webLink(URL)
    /// Plain text, Wi-Fi credentials, phone numbers… → ALERT_INVALID_QR without a link.
    case other

    /// Lower-cased host without "www." for alert copy ("This QR code opens example.com…").
    var displayDomain: String? {
        guard case .webLink(let url) = self, var host = url.host()?.lowercased() else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
