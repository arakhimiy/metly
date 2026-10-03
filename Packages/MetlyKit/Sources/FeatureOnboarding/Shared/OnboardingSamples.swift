import Foundation
import MetlyCore

/// Sample data for the welcome illustrations and previews (prototype personas, SPEC §2.5.1).
enum OnboardingSamples {
    static let ownerCard = CardFaceContent(
        fullName: "Aziza Karimova",
        jobTitle: "Product Designer",
        company: "Tezkor Labs",
        fields: [
            ContactField(kind: .phone, value: "+998 90 123 45 67"),
            ContactField(kind: .email, value: "aziza@tezkor.uz"),
            ContactField(kind: .telegram, value: "@aziza.k"),
        ],
        qrPayload: Brand.cardURL(slug: "aziza").absoluteString
    )

    static let workDesign = CardDesign(template: .professional, palette: .ink, appearance: .dark)
    static let personalDesign = CardDesign(template: .stack, palette: .sand, appearance: .light, font: .rounded)

    static let contactName = "Jasur Toshmatov"
    static let contactRole = "Founder · Payline"
    static let eventName = "Tashkent Tech Week"
    static let placeName = "Hyatt Regency"

    static let invite = DeferredInvite(
        ownerName: contactName,
        ownerTitle: "Founder, Payline",
        eventName: eventName,
        card: CardSnapshot(
            cardName: "Work",
            design: CardDesign(template: .modern, palette: .graphite, appearance: .dark),
            fullName: contactName,
            jobTitle: "Founder",
            company: "Payline",
            fields: [
                ContactField(kind: .telegram, value: "@jasur.t"),
                ContactField(kind: .email, value: "jasur@payline.uz"),
            ],
            url: Brand.cardURL(slug: "jasur-p4y1")
        ),
        cardSlug: "jasur-p4y1"
    )

    static let inviteWithoutEvent = DeferredInvite(
        ownerName: invite.ownerName,
        ownerTitle: invite.ownerTitle,
        eventName: nil,
        card: invite.card,
        cardSlug: invite.cardSlug
    )
}
