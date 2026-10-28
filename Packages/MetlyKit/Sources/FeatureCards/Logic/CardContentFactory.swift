import Foundation
import MetlyCardKit
import MetlyCore
import MetlyData

/// Builds the values rendered on a card face for an audience (SPEC §9 Q4):
/// in-app previews use `.connections`; anything that can leave the device (exports, Wallet,
/// Lock Screen, offline QR vCard) uses `.public`. Private never appears anywhere.
nonisolated enum CardContentFactory {
    static func content(fullName: String, jobTitle: String, company: String, photoData: Data?, logoData: Data?,
                        contacts selected: [ContactEntry], audience: CardAudience, qrPayload: String) -> CardFaceContent {
        let visible = selected.filter { !$0.isEmpty && audience.allows($0.privacy) }
        return CardFaceContent(fullName: fullName, jobTitle: jobTitle, company: company,
                               photoData: photoData, logoData: logoData,
                               fields: ContactFieldKind.allCases.compactMap { visible.first(of: $0)?.field },
                               qrPayload: qrPayload,
                               additionalPhones: Array(visible.entries(of: .phone).dropFirst().map(\.labeledPhone)),
                               phoneLabel: visible.legacyPhoneLabel,
                               contacts: visible)
    }

    /// The offline QR / unpublished export payload: a vCard of the public content (+ link when published).
    static func vCard(for publicContent: CardFaceContent, url: URL?) -> String {
        VCardBuilder.make(content: publicContent, url: url)
    }
}

extension CardContentFactory {
    /// Face content for a design that may not be saved yet (create wizard, editor draft).
    @MainActor
    /// - Parameter selection: the card's chosen entries (`Card.visibleContactIDs`); nil = a card from before
    ///   3.0.0, shown by `design.visibleFields`.
    static func content(profile: Profile?, design: CardDesign, selection: [UUID]?, audience: CardAudience,
                        qrPayload: String, photo: MediaEdit = .unchanged, logo: MediaEdit = .unchanged) -> CardFaceContent {
        guard let profile else { return CardFaceContent(fullName: "", qrPayload: qrPayload) }
        return content(fullName: profile.fullName, jobTitle: profile.jobTitle, company: profile.company,
                       photoData: photo.resolved(profile.photoData), logoData: logo.resolved(profile.logoData),
                       contacts: profile.contacts(selectedBy: selection, design: design), audience: audience,
                       qrPayload: qrPayload)
    }

    /// In-app preview of a stored card (owner's view: Public + Connections).
    @MainActor
    static func preview(of card: Card, profile: Profile?) -> CardFaceContent {
        content(profile: profile, design: card.design, selection: card.visibleContactIDs, audience: .connections,
                qrPayload: card.url?.absoluteString ?? "")
    }

    /// Content for everything that leaves the device. Its QR encodes the card link, or — while the
    /// card has no slug yet — a vCard so the printed / saved code still works.
    @MainActor
    static func shareable(_ card: Card, profile: Profile?) -> CardFaceContent {
        var content = content(profile: profile, design: card.design, selection: card.visibleContactIDs, audience: .public,
                              qrPayload: "")
        content.qrPayload = card.url?.absoluteString ?? vCard(for: content, url: nil)
        return content
    }
}
