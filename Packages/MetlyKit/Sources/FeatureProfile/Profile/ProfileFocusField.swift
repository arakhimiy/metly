import MetlyCore

/// Text fields on PROFILE, in keyboard "Next" order.
enum ProfileFocusField: Hashable {
    case name, jobTitle, company
    case contact(ContactFieldKind)

    /// The field the Return key moves to (nil after the last one).
    var next: ProfileFocusField? {
        switch self {
        case .name: .jobTitle
        case .jobTitle: .company
        case .company: .contact(.phone)
        case .contact(let kind):
            ContactFieldKind.allCases.firstIndex(of: kind).flatMap { index in
                let nextIndex = ContactFieldKind.allCases.index(after: index)
                return nextIndex < ContactFieldKind.allCases.endIndex ? .contact(ContactFieldKind.allCases[nextIndex]) : nil
            }
        }
    }
}
