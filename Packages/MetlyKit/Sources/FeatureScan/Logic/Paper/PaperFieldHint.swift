import Foundation
import MetlyCore

/// How sure PAPER_REVIEW is about a value read from the card.
nonisolated enum PaperFieldHint: Equatable, Sendable {
    /// The value has a recognisable format (phone digits, an email address, a link or handle).
    case detected
    /// Picked from the card's layout (name, title, company) or an odd-looking value — worth a check.
    case guessed

    /// Hints for every non-empty field of an OCR draft. Values the user edits drop their hint.
    static func assess(_ draft: PaperCardDraft) -> [PaperField: PaperFieldHint] {
        var hints: [PaperField: PaperFieldHint] = [:]
        for field in [PaperField.name, .title, .company] where !draft.value(for: field).isEmpty {
            hints[field] = .guessed
        }
        for contact in draft.fields where !contact.isEmpty {
            let field = PaperField(kind: contact.kind)
            hints[field] = isWellFormed(contact) ? .detected : .guessed
        }
        return hints
    }

    static func isWellFormed(_ field: ContactField) -> Bool {
        let value = field.value.trimmingCharacters(in: .whitespaces)
        switch field.kind {
        case .phone:
            return PhoneFormat.isPlausible(value)
        case .email:
            return value.wholeMatch(of: /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/) != nil
        case .telegram:
            return value.wholeMatch(of: /@?[A-Za-z0-9_.]{3,32}/) != nil
        case .website:
            return value.contains(".") && !value.contains(" ")
        case .linkedin:
            return value.lowercased().hasPrefix("in/") || value.lowercased().contains("linkedin.com")
        }
    }
}
