import MetlyCore
import MetlyDesign
import SwiftUI

/// Editable contact list as a Form section: one row per entry (phones with a label menu — Mobile / Work /
/// Home / Other), delete with − or a swipe, "+ Add Contact" for a phone, Telegram, WhatsApp, Instagram,
/// email, website or LinkedIn.
///
/// ```swift
/// Form {
///     ContactInfoEditor(draft: $contactInfo)
/// }
/// // Save: contactInfo.apply(to: connection)
/// ```
public struct ContactInfoEditor: View {
    @Binding var draft: ContactInfoDraft

    @FocusState private var focusedEntry: ContactEntry.ID?

    public init(draft: Binding<ContactInfoDraft>) {
        _draft = draft
    }

    public var body: some View {
        Section {
            ForEach($draft.entries) { $entry in
                EntryEditRow(entry: $entry, isFocused: focusedEntry == entry.id) { delete(entry.id) }
                    .focused($focusedEntry, equals: entry.id)
            }
            .onDelete { draft.remove(atOffsets: $0) }
            AddContactMenu(isEnabled: draft.canAdd, action: add)
        } header: {
            Text("Contact Info")
        } footer: {
            if !draft.canAdd {
                Text("You can save up to \(ContactEntry.maxCount) contacts.")
            }
        }
        .sensoryFeedback(.selection, trigger: draft.entries.compactMap(\.label))
    }

    private func add(_ kind: ContactFieldKind) {
        guard let id = draft.add(kind) else { return }
        Task { focusedEntry = id }
    }

    private func delete(_ id: ContactEntry.ID) {
        withAnimation {
            draft.remove(id: id)
        }
    }
}

/// − · (Mobile ⌃⌄ or the kind's icon) · value — like Contacts' edit mode.
private struct EntryEditRow: View {
    @Binding var entry: ContactEntry
    /// The note waits until the user leaves the field.
    let isFocused: Bool
    let onDelete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row
            if let problem = ContactFieldInput.problem(entry.value, for: entry.kind), !isFocused {
                ContactProblemNote(problem).padding(.leading, 56).padding(.bottom, 8)
            }
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 16))
    }

    private var row: some View {
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
            .accessibilityLabel(Text("Delete \(title)"))

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                if entry.kind == .phone {
                    Picker("Label", selection: Binding { entry.label ?? .mobile } set: { entry.label = $0 }) {
                        ForEach(PhoneLabel.allCases) { label in
                            Label(label.title, systemImage: label.symbolName).tag(label)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                    .accessibilityLabel("Phone Label")
                } else {
                    SettingsIcon(field: entry.kind)
                }

                TextField(entry.kind.title, text: typedValue,
                          prompt: Text(verbatim: ContactFieldInput.placeholder(for: entry.kind)))
                    .keyboardType(ContactFieldInput.keyboardType(for: entry.kind))
                    .textContentType(ContactFieldInput.contentType(for: entry.kind))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityLabel(Text(title))
            }
        }
    }

    /// Spaced phone numbers, username characters only, capped at the server limit.
    private var typedValue: Binding<String> {
        Binding { entry.value } set: { text in
            entry.value = String(ContactFieldInput.typing(text, for: entry.kind).prefix(ContactEntry.maxLength(for: entry.kind)))
        }
    }

    private var title: String {
        entry.kind == .phone ? String(localized: "\((entry.label ?? .mobile).title) Number") : entry.kind.title
    }
}

#Preview("Contact Info · editing") {
    @Previewable @State var draft = ContactInfoDraft(entries: [
        ContactEntry(kind: .phone, label: .mobile, value: "+998 90 123 45 67"),
        ContactEntry(kind: .phone, label: .work, value: "+998 71 200 00 00"),
        ContactEntry(kind: .email, value: "kamila@uzum.uz"),
        ContactEntry(kind: .telegram, value: "@kamila.y"),
        ContactEntry(kind: .instagram, value: "@kamila.design"),
    ])
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
