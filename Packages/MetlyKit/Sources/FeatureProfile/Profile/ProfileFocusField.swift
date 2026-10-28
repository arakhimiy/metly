import Foundation
import MetlyCore

/// Text fields on PROFILE, in keyboard "Next" order: name, job title, company, then the contact entries in
/// their order.
enum ProfileFocusField: Hashable {
    case name, jobTitle, company
    case contact(UUID)

    /// The field the Return key moves to (nil after the last one), given the contact entries in order.
    func next(contactIDs ids: [UUID]) -> ProfileFocusField? {
        switch self {
        case .name: return .jobTitle
        case .jobTitle: return .company
        case .company: return ids.first.map(ProfileFocusField.contact)
        case .contact(let id):
            guard let index = ids.firstIndex(of: id), index + 1 < ids.count else { return nil }
            return .contact(ids[index + 1])
        }
    }
}
