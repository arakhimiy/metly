import Foundation
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

    /// The sample person with a work and a home number after her mobile.
    static let sampleSeveralPhones = CardFaceContent(
        fullName: sample.fullName,
        jobTitle: sample.jobTitle,
        company: sample.company,
        fields: sample.fields,
        qrPayload: sample.qrPayload,
        additionalPhones: [
            LabeledPhone(id: UUID(uuidString: "5A1D0000-0000-4000-8000-000000000001")!, label: .work,
                         value: "+998 71 200 10 20", privacy: .public),
            LabeledPhone(id: UUID(uuidString: "5A1D0000-0000-4000-8000-000000000002")!, label: .home,
                         value: "+998 71 255 33 44 ext. 1290", privacy: .public),
        ],
        phoneLabel: .mobile
    )

    /// Name only — checks fallbacks (initials, monogram, empty contacts).
    static let sampleMinimal = CardFaceContent(fullName: "Timur Sobirov", qrPayload: Brand.cardURL(slug: "timur-2k9d").absoluteString)
}
