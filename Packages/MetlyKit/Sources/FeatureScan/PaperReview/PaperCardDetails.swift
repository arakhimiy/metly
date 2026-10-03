import Foundation
import MetlyCore
import MetlyData

/// The editable values on PAPER_REVIEW.
struct PaperCardDetails: Equatable {
    var fullName: String
    var jobTitle: String
    var company: String
    var phone: String
    var email: String
    var telegram: String
    var website: String
    var linkedin: String

    init(draft: PaperCardDraft) {
        fullName = draft.fullName
        jobTitle = draft.jobTitle
        company = draft.company
        phone = draft.value(for: .phone)
        email = draft.value(for: .email)
        telegram = draft.value(for: .telegram)
        website = draft.value(for: .website)
        linkedin = draft.value(for: .linkedin)
    }

    subscript(field: PaperField) -> String {
        get {
            switch field {
            case .name: fullName
            case .title: jobTitle
            case .company: company
            case .phone: phone
            case .email: email
            case .telegram: telegram
            case .website: website
            case .linkedin: linkedin
            }
        }
        set {
            switch field {
            case .name: fullName = newValue
            case .title: jobTitle = newValue
            case .company: company = newValue
            case .phone: phone = newValue
            case .email: email = newValue
            case .telegram: telegram = newValue
            case .website: website = newValue
            case .linkedin: linkedin = newValue
            }
        }
    }

    /// A connection needs a name.
    var canSave: Bool {
        !fullName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Non-empty contact values, trimmed, in display order.
    var contactFields: [ContactField] {
        ContactFieldKind.allCases.compactMap { kind in
            let value = self[PaperField(kind: kind)].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : ContactField(kind: kind, value: value)
        }
    }

    var draft: PaperCardDraft {
        PaperCardDraft(fullName: fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                       jobTitle: jobTitle.trimmingCharacters(in: .whitespacesAndNewlines),
                       company: company.trimmingCharacters(in: .whitespacesAndNewlines),
                       fields: contactFields)
    }
}
