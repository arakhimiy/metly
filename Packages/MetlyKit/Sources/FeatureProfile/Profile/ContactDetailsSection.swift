import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "Contact Details": one row per field kind (fixed order) with inline value + privacy menu.
/// Phones work like Contacts: the primary number with its label, then extra labelled numbers
/// (each with its own privacy, swipe to delete) and "Add Phone" (up to 5 extra numbers).
struct ContactDetailsSection: View {
    let profile: Profile
    var focusedField: FocusState<ProfileFocusField?>.Binding

    var body: some View {
        let editor = profile.editor
        let extraIDs = profile.additionalPhones.map(\.id)
        Section {
            PhoneNumberRow(label: editor.phoneLabelBinding(), value: editor.valueBinding(for: .phone),
                           privacy: editor.privacyBinding(for: .phone),
                           privacyTitle: String(localized: "Who Can See Your \(ContactFieldKind.phone.title)"),
                           focus: .contact(.phone),
                           nextFocus: ProfileFocusField.contact(.phone).next(extraPhoneIDs: extraIDs),
                           focusedField: focusedField)

            ForEach(profile.additionalPhones) { phone in
                let focus = ProfileFocusField.extraPhone(phone.id)
                PhoneNumberRow(label: editor.extraPhoneLabelBinding(id: phone.id),
                               value: editor.extraPhoneValueBinding(id: phone.id),
                               privacy: editor.extraPhonePrivacyBinding(id: phone.id),
                               privacyTitle: String(localized: "Who Can See This Number"),
                               focus: focus, nextFocus: focus.next(extraPhoneIDs: extraIDs),
                               focusedField: focusedField)
            }
            .onDelete(perform: profile.removePhones(atOffsets:))

            if profile.canAddPhone {
                AddPhoneRow(action: addPhone)
            }

            ForEach(ContactFieldKind.allCases.filter { $0 != .phone }) { kind in
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

    /// Adds an empty number and moves the keyboard to it (left empty, it goes away again).
    private func addPhone() {
        guard let id = profile.addPhone() else { return }
        let focusedField = focusedField
        // Next run loop: the new row has to exist before it can take focus.
        Task { focusedField.wrappedValue = .extraPhone(id) }
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
