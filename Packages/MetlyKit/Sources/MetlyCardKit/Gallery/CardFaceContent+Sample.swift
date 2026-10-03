import MetlyCore

public extension CardFaceContent {
    /// Sample person used by template galleries, palette pickers and previews.
    static let sample = CardFaceContent(
        fullName: "Kamola Rashidova",
        jobTitle: "Product Designer",
        company: "Tezkor",
        fields: [
            ContactField(kind: .phone, value: "+998 90 123 45 67", privacy: .public),
            ContactField(kind: .email, value: "kamola@tezkor.uz", privacy: .public),
            ContactField(kind: .telegram, value: "@kamola.r", privacy: .public),
            ContactField(kind: .website, value: "kamola.design", privacy: .public),
            ContactField(kind: .linkedin, value: "in/kamolarashidova", privacy: .public),
        ],
        qrPayload: Brand.cardURL(slug: "kamola-7f3k").absoluteString
    )

    /// Same person with long values, to check ellipsis and wrapping.
    static let sampleLong = CardFaceContent(
        fullName: "Alexandrina Konstantinopolskaya-Vasquez",
        jobTitle: "Head of International Partnerships and Developer Relations",
        company: "Northern Silk Road Ventures International",
        fields: [
            ContactField(kind: .phone, value: "+998 90 123 45 67 ext. 4421", privacy: .public),
            ContactField(kind: .email, value: "alexandrina.konstantinopolskaya@silkroadventures.international", privacy: .public),
            ContactField(kind: .telegram, value: "@alexandrina_konstantinopolskaya", privacy: .public),
            ContactField(kind: .website, value: "silkroadventures.international/team/alexandrina", privacy: .public),
            ContactField(kind: .linkedin, value: "in/alexandrina-konstantinopolskaya-vasquez", privacy: .public),
        ],
        qrPayload: Brand.cardURL(slug: "alexandrina-x9q2").absoluteString
    )

    /// Name only — checks fallbacks (initials, monogram, empty contacts).
    static let sampleMinimal = CardFaceContent(fullName: "Timur Sobirov", qrPayload: Brand.cardURL(slug: "timur-2k9d").absoluteString)
}
