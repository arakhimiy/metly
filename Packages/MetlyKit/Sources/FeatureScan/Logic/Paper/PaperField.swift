import MetlyCore
import UIKit

/// The editable rows of PAPER_REVIEW "Detected Details".
nonisolated enum PaperField: String, CaseIterable, Identifiable, Hashable, Sendable {
    case name, title, company, phone, email, telegram, website, linkedin

    var id: String { rawValue }

    init(kind: ContactFieldKind) {
        switch kind {
        case .phone: self = .phone
        case .email: self = .email
        case .telegram: self = .telegram
        case .website: self = .website
        case .linkedin: self = .linkedin
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
        }
    }

    var title: String {
        switch self {
        case .name: "Name"
        case .title: "Title"
        case .company: "Company"
        default: kind?.title ?? ""
        }
    }

    var placeholder: String {
        switch self {
        case .name: "Full Name"
        case .title: "Job Title"
        case .company: "Company"
        case .phone: "+998 90 123 45 67"
        case .email: "name@company.com"
        case .telegram: "@username"
        case .website: "company.com"
        case .linkedin: "in/username"
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
        case .phone: .telephoneNumber
        case .email: .emailAddress
        case .telegram: .username
        case .website, .linkedin: .URL
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .name, .title, .company: .default
        case .phone: .phonePad
        case .email: .emailAddress
        case .telegram: .asciiCapable
        case .website, .linkedin: .URL
        }
    }

    /// Names, titles and companies are capitalised; contact values are typed as-is.
    var capitalizesWords: Bool {
        switch self {
        case .name, .title, .company: true
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
