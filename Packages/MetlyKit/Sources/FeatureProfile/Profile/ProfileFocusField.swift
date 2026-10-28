import Foundation
import MetlyCore

/// Text fields on PROFILE, in keyboard "Next" order (extra phone numbers follow the primary one).
enum ProfileFocusField: Hashable {
    case name, jobTitle, company
    case contact(ContactFieldKind)
    case extraPhone(UUID)

    /// The field the Return key moves to (nil after the last one), ignoring extra phone numbers.
    var next: ProfileFocusField? { next(extraPhoneIDs: []) }

    /// The field the Return key moves to, given the extra phone numbers in display order.
    func next(extraPhoneIDs ids: [UUID]) -> ProfileFocusField? {
        switch self {
        case .name: return .jobTitle
        case .jobTitle: return .company
        case .company: return .contact(.phone)
        case .contact(.phone):
            return ids.first.map(ProfileFocusField.extraPhone) ?? Self.field(after: .phone)
        case .extraPhone(let id):
            if let index = ids.firstIndex(of: id), index + 1 < ids.count { return .extraPhone(ids[index + 1]) }
            return Self.field(after: .phone)
        case .contact(let kind):
            return Self.field(after: kind)
        }
    }

    private static func field(after kind: ContactFieldKind) -> ProfileFocusField? {
        let kinds = ContactFieldKind.allCases
        guard let index = kinds.firstIndex(of: kind) else { return nil }
        let nextIndex = kinds.index(after: index)
        return nextIndex < kinds.endIndex ? .contact(kinds[nextIndex]) : nil
    }
}
