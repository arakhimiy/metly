import MetlyCardKit
import MetlyCore
import MetlyDesign
import SwiftUI

/// A phone row in Contact Details, like Contacts: the label menu ("Mobile ⌃⌄") sits where other rows
/// show their title, the number below it, the privacy menu trailing. The tile shows the label's glyph.
/// Stacks vertically at accessibility text sizes so nothing truncates.
struct PhoneNumberRow: View {
    @Binding var label: PhoneLabel
    @Binding var value: String
    @Binding var privacy: FieldPrivacy
    /// Header of the privacy menu.
    let privacyTitle: String
    let focus: ProfileFocusField
    let nextFocus: ProfileFocusField?
    var focusedField: FocusState<ProfileFocusField?>.Binding

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            SettingsIcon(label.tileSymbolName, color: ContactFieldKind.phone.tint)
            VStack(alignment: .leading, spacing: 2) {
                PhoneLabelMenu(label: $label)
                TextField(ContactFieldRules.placeholder(for: .phone), text: $value)
                    .keyboardType(ContactFieldRules.keyboardType(for: .phone))
                    .textContentType(ContactFieldRules.contentType(for: .phone))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(nextFocus == nil ? .done : .next)
                    .focused(focusedField, equals: focus)
                    .onSubmit { focusedField.wrappedValue = nextFocus }
                    .accessibilityLabel(Text(label.phoneNumberTitle))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            FieldPrivacyMenu(title: privacyTitle, fieldName: label.phoneNumberTitle, privacy: $privacy)
        }
    }
}
