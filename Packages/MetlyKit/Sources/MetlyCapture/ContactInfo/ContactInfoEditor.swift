import MetlyCore
import MetlyDesign
import SwiftUI

/// Editable contact values as Form sections: **Phone Numbers** (label menu per number — Mobile / Work /
/// Home / Other — add and delete) and **Contact Info** (email, Telegram, website, LinkedIn).
///
/// ```swift
/// Form {
///     ContactInfoEditor(draft: $contactInfo)
/// }
/// // Save: contactInfo.apply(to: connection)
/// ```
public struct ContactInfoEditor: View {
    @Binding var draft: ContactInfoDraft

    @FocusState private var focusedPhone: LabeledPhone.ID?

    public init(draft: Binding<ContactInfoDraft>) {
        _draft = draft
    }

    public var body: some View {
        Section {
            ForEach($draft.phones) { $phone in
                PhoneEditRow(phone: $phone) { delete(phone.id) }
                    .focused($focusedPhone, equals: phone.id)
            }
            .onDelete { draft.removePhones(atOffsets: $0) }
            Button("Add Phone", systemImage: "plus.circle.fill", action: addPhone)
        } header: {
            Text("Phone Numbers")
        }
        .sensoryFeedback(.selection, trigger: draft.phones.map(\.label))

        Section("Contact Info") {
            ContactValueRow(kind: .email, value: $draft.email)
            ContactValueRow(kind: .telegram, value: $draft.telegram)
            ContactValueRow(kind: .website, value: $draft.website)
            ContactValueRow(kind: .linkedin, value: $draft.linkedin)
        }
    }

    private func addPhone() {
        focusedPhone = draft.addPhone()
    }

    private func delete(_ id: LabeledPhone.ID) {
        withAnimation {
            draft.removePhone(id: id)
        }
    }
}

/// − · Mobile ⌃⌄ · number — like Contacts' edit mode.
private struct PhoneEditRow: View {
    @Binding var phone: LabeledPhone
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .red)
                    .font(.title3)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Delete \(phone.label.title) Number"))

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                Picker("Label", selection: $phone.label) {
                    ForEach(PhoneLabel.allCases) { label in
                        Label(label.title, systemImage: label.symbolName).tag(label)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Phone Label")

                TextField("Phone", text: $phone.value,
                          prompt: Text(verbatim: ContactFieldInput.placeholder(for: .phone)))
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
                    .accessibilityLabel(Text("\(phone.label.title) Number"))
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
    }
}

/// Icon + text field for one non-phone value.
private struct ContactValueRow: View {
    let kind: ContactFieldKind
    @Binding var value: String

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(field: kind)
            TextField(kind.title, text: $value, prompt: Text(verbatim: ContactFieldInput.placeholder(for: kind)))
                .keyboardType(ContactFieldInput.keyboardType(for: kind))
                .textContentType(ContactFieldInput.contentType(for: kind))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(kind.title)
        }
    }
}

#Preview("Contact Info · editing") {
    @Previewable @State var draft = ContactInfoDraft(
        phones: [LabeledPhone(id: LabeledPhone.primaryID, label: .mobile, value: "+998 90 123 45 67"),
                 LabeledPhone(label: .work, value: "+998 71 200 00 00")],
        email: "kamila@uzum.uz", telegram: "@kamila.y")
    NavigationStack {
        Form { ContactInfoEditor(draft: $draft) }
            .navigationTitle("Edit Context")
            .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Contact Info · empty") {
    @Previewable @State var draft = ContactInfoDraft()
    NavigationStack {
        Form { ContactInfoEditor(draft: $draft) }
    }
}
