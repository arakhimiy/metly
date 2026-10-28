import MetlyCore
import UIKit

/// The editable rows of PAPER_REVIEW "Detected Details".
nonisolated enum PaperField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, title, company, phone, email, telegram, website, linkedin, whatsapp, instagram, address

    var id: String { rawValue }

    init(kind: ContactFieldKind) {
        switch kind {
        case .phone: self = .phone
        case .email: self = .email
        case .telegram: self = .telegram
        case .website: self = .website
        case .linkedin: self = .linkedin
        case .whatsapp: self = .whatsapp
        case .instagram: self = .instagram
        case .address: self = .address
        }
    }

    /// The contact kind behind the row (nil for name / title / company).
    var kind: ContactFieldKind? {
        switch self {
        case .name, .title, .company: nil
        case .phone: .phone
        case .email: .email
        case .telegram: .telegram
        case .website: .website
        case .linkedin: .linkedin
        case .whatsapp: .whatsapp
        case .instagram: .instagram
        case .address: .address
        }
    }

    var title: String {
        switch self {
        case .name: String(localized: "Name")
        case .title: String(localized: "Title")
        case .company: String(localized: "Company")
        default: kind?.title ?? ""
        }
    }

    var placeholder: String {
        switch self {
        case .name: String(localized: "Full Name")
        case .title: String(localized: "Job Title")
        case .company: String(localized: "Company")
        case .phone: "+998 90 123 45 67"
        case .email: "name@company.com"
        case .telegram: "@username"
        case .website: "company.com"
        case .linkedin: "in/username"
        case .whatsapp: "+998 90 123 45 67"
        case .instagram: "@username"
        case .address: String(localized: "Street, building, city")
        }
    }

    var symbolName: String {
        switch self {
        case .name: "person.fill"
        case .title: "briefcase.fill"
        case .company: "building.2.fill"
        default: kind?.symbolName ?? "questionmark"
        }
    }

    var contentType: UITextContentType {
        switch self {
        case .name: .name
        case .title: .jobTitle
        case .company: .organizationName
        case .phone, .whatsapp: .telephoneNumber
        case .email: .emailAddress
        case .telegram, .instagram: .username
        case .website, .linkedin: .URL
        case .address: .fullStreetAddress
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .name, .title, .company, .address: .default
        case .phone, .whatsapp: .phonePad
        case .email: .emailAddress
        case .telegram, .instagram: .asciiCapable
        case .website, .linkedin: .URL
        }
    }

    /// Names, titles and companies are capitalised; contact values are typed as-is.
    var capitalizesWords: Bool {
        switch self {
        case .name, .title, .company, .address: true
        default: false
        }
    }
}

extension PaperCardDraft {
    nonisolated func value(for field: PaperField) -> String {
        switch field {
        case .name: fullName
        case .title: jobTitle
        case .company: company
        default: fields.first { $0.kind == field.kind }?.value ?? ""
        }
    }
}
