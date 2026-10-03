import Foundation
import MetlyCardKit
import MetlyCore
import MetlyData

/// Builds the values rendered on a card face for an audience (SPEC §9 Q4):
/// in-app previews use `.connections`; anything that can leave the device (exports, Wallet,
/// Lock Screen, offline QR vCard) uses `.public`. Private never appears anywhere.
nonisolated enum CardContentFactory {
    /// Non-empty, audience-allowed, design-visible fields in display order.
    static func fields(_ fields: [ContactField], visible: Set<ContactFieldKind>, audience: CardAudience) -> [ContactField] {
        ContactFieldKind.allCases.compactMap { kind in
            fields.first { $0.kind == kind && !$0.isEmpty && audience.allows($0.privacy) && visible.contains(kind) }
        }
    }

    static func content(fullName: String, jobTitle: String, company: String, photoData: Data?, logoData: Data?,
                        fields allFields: [ContactField], design: CardDesign, audience: CardAudience,
                        qrPayload: String) -> CardFaceContent {
        CardFaceContent(fullName: fullName, jobTitle: jobTitle, company: company,
                        photoData: photoData, logoData: logoData,
                        fields: fields(allFields, visible: design.visibleFields, audience: audience),
                        qrPayload: qrPayload)
    }

    /// The offline QR / unpublished export payload: a vCard of the public content (+ link when published).
    static func vCard(for publicContent: CardFaceContent, url: URL?) -> String {
        VCardBuilder.make(content: publicContent, url: url)
    }
}

extension CardContentFactory {
    /// Face content for a design that may not be saved yet (create wizard, editor draft).
    @MainActor
    static func content(profile: Profile?, design: CardDesign, audience: CardAudience, qrPayload: String,
                        photo: MediaEdit = .unchanged, logo: MediaEdit = .unchanged) -> CardFaceContent {
        guard let profile else { return CardFaceContent(fullName: "", qrPayload: qrPayload) }
        return content(fullName: profile.fullName, jobTitle: profile.jobTitle, company: profile.company,
                       photoData: photo.resolved(profile.photoData), logoData: logo.resolved(profile.logoData),
                       fields: profile.contactFields, design: design, audience: audience, qrPayload: qrPayload)
    }

    /// In-app preview of a stored card (owner's view: Public + Connections).
    @MainActor
    static func preview(of card: Card, profile: Profile?) -> CardFaceContent {
        content(profile: profile, design: card.design, audience: .connections,
                qrPayload: card.url?.absoluteString ?? "")
    }

    /// Content for everything that leaves the device. Its QR encodes the card link, or — while the
    /// card has no slug yet — a vCard so the printed / saved code still works.
    @MainActor
    static func shareable(_ card: Card, profile: Profile?) -> CardFaceContent {
        var content = content(profile: profile, design: card.design, audience: .public, qrPayload: "")
        content.qrPayload = card.url?.absoluteString ?? vCard(for: content, url: nil)
        return content
    }
}
