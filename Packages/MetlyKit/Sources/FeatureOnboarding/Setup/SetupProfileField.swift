import SwiftUI

/// Text fields of SETUP_PROFILE, in focus order.
enum SetupProfileField: CaseIterable, Hashable {
    case fullName, jobTitle, company, phone, email, telegram

    var title: LocalizedStringKey {
        switch self {
        case .fullName: "Full Name"
        case .jobTitle: "Job Title"
        case .company: "Company"
        case .phone: "Phone"
        case .email: "Email"
        case .telegram: "Telegram Username"
        }
    }

    var contentType: UITextContentType {
        switch self {
        case .fullName: .name
        case .jobTitle: .jobTitle
        case .company: .organizationName
        case .phone: .telephoneNumber
        case .email: .emailAddress
        case .telegram: .username
        }
    }

    var keyboard: UIKeyboardType {
        switch self {
        case .phone: .phonePad
        case .email: .emailAddress
        case .telegram: .asciiCapable
        default: .default
        }
    }

    var capitalization: TextInputAutocapitalization {
        switch self {
        case .fullName, .company: .words
        case .jobTitle: .sentences
        case .phone, .email, .telegram: .never
        }
    }

    var disablesAutocorrection: Bool {
        switch self {
        case .phone, .email, .telegram: true
        default: false
        }
    }

    var next: SetupProfileField? {
        let all = Self.allCases
        guard let index = all.firstIndex(of: self), index + 1 < all.count else { return nil }
        return all[index + 1]
    }
}

/// A Form row text field configured for its content type.
struct SetupTextField: View {
    let field: SetupProfileField
    @Binding var text: String
    var focus: FocusState<SetupProfileField?>.Binding

    var body: some View {
        TextField(field.title, text: $text)
            .textContentType(field.contentType)
            .keyboardType(field.keyboard)
            .textInputAutocapitalization(field.capitalization)
            .autocorrectionDisabled(field.disablesAutocorrection)
            .submitLabel(field.next == nil ? .done : .next)
            .focused(focus, equals: field)
    }
}
