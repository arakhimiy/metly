import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "Contact Details": one row per field kind (fixed order) with inline value + privacy menu.
struct ContactDetailsSection: View {
    let profile: Profile
    var focusedField: FocusState<ProfileFocusField?>.Binding

    var body: some View {
        let editor = profile.editor
        Section {
            ForEach(ContactFieldKind.allCases) { kind in
                LabeledFieldRow(title: kind.title) {
                    SettingsIcon(field: kind)
                } field: {
                    ContactValueField(kind: kind, value: editor.valueBinding(for: kind), focusedField: focusedField)
                } accessory: {
                    FieldPrivacyMenu(kind: kind, privacy: editor.privacyBinding(for: kind))
                }
            }
        } header: {
            Text("Contact Details")
        } footer: {
            Text("Public: anyone with your link. Connections: people you’ve connected with. Private: only you — it never appears on a card.")
        }
    }
}

/// Text field configured for the field kind (keyboard, autofill, no autocorrect).
private struct ContactValueField: View {
    let kind: ContactFieldKind
    @Binding var value: String
    var focusedField: FocusState<ProfileFocusField?>.Binding

    var body: some View {
        TextField(ContactFieldRules.placeholder(for: kind), text: $value)
            .keyboardType(ContactFieldRules.keyboardType(for: kind))
            .textContentType(ContactFieldRules.contentType(for: kind))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(ProfileFocusField.contact(kind).next == nil ? .done : .next)
            .focused(focusedField, equals: .contact(kind))
            .onSubmit { focusedField.wrappedValue = ProfileFocusField.contact(kind).next }
    }
}
