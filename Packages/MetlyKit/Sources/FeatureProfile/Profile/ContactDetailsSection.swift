import MetlyCardKit
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "Contact Details": the owner's contact list in their order — only what they added, nothing empty
/// waiting to be filled. Each row has its value and privacy (phones also their label, like Contacts);
/// swipe to delete. "+ Add Contact" picks a kind (Phone, Telegram, WhatsApp, Instagram…), up to
/// `ContactEntry.maxCount`. Tapping it while a row is still empty moves to that row instead of stacking
/// another blank one; a row left empty goes away.
struct ContactDetailsSection: View {
    let profile: Profile
    var focusedField: FocusState<ProfileFocusField?>.Binding

    var body: some View {
        let editor = profile.editor
        let ids = profile.contacts.map(\.id)
        Section {
            ForEach(profile.contacts) { entry in
                let focus = ProfileFocusField.contact(entry.id)
                if entry.kind == .phone {
                    PhoneNumberRow(label: editor.labelBinding(id: entry.id), value: editor.valueBinding(id: entry.id),
                                   privacy: editor.privacyBinding(id: entry.id),
                                   privacyTitle: String(localized: "Who Can See This Number"),
                                   focus: focus, nextFocus: focus.next(contactIDs: ids), focusedField: focusedField)
                } else {
                    LabeledFieldRow(title: entry.kind.title) {
                        SettingsIcon(field: entry.kind)
                    } field: {
                        ContactValueField(kind: entry.kind, value: editor.valueBinding(id: entry.id), focus: focus,
                                          nextFocus: focus.next(contactIDs: ids), focusedField: focusedField)
                    } accessory: {
                        FieldPrivacyMenu(kind: entry.kind, privacy: editor.privacyBinding(id: entry.id))
                    }
                }
            }
            .onDelete { offsets in
                profile.removeContacts(ids: Set(offsets.map { profile.contacts[$0].id }))
            }

            AddContactMenu(isEnabled: profile.canAddContact, action: add)
        } header: {
            Text("Contact Details")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Public: anyone with your link. Connections: people you’ve connected with. Private: only you — it never appears on a card.")
                if !profile.canAddContact {
                    Text("You can add up to \(ContactEntry.maxCount) contacts.")
                }
            }
        }
    }

    /// Adds an entry (or reuses the empty one) and moves the keyboard to it.
    private func add(_ kind: ContactFieldKind) {
        guard let id = profile.addContact(kind) else { return }
        let focusedField = focusedField
        // Next run loop: the new row has to exist before it can take focus.
        Task { focusedField.wrappedValue = .contact(id) }
    }
}

/// Text field configured for the entry's kind (keyboard, autofill, no autocorrect).
private struct ContactValueField: View {
    let kind: ContactFieldKind
    @Binding var value: String
    let focus: ProfileFocusField
    let nextFocus: ProfileFocusField?
    var focusedField: FocusState<ProfileFocusField?>.Binding

    var body: some View {
        TextField(ContactFieldRules.placeholder(for: kind), text: $value)
            .keyboardType(ContactFieldRules.keyboardType(for: kind))
            .textContentType(ContactFieldRules.contentType(for: kind))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(nextFocus == nil ? .done : .next)
            .focused(focusedField, equals: focus)
            .onSubmit { focusedField.wrappedValue = nextFocus }
    }
}
