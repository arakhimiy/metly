import MetlyCore
import MetlyDesign
import SwiftUI

/// "Contact Info": what the camera read — every number with its label (Mobile / Work / Home / Other), then
/// Telegram, WhatsApp, Instagram, email, website, LinkedIn and the address — only the ones found. Swipe to
/// delete; **+ Add Contact** (the same menu as PROFILE) for one the camera missed. A row left empty goes away.
/// The first mobile is saved as the main number.
struct PaperContactInfoSection: View {
    @Binding var details: PaperCardDetails
    /// Rows added with + Add Contact that are still empty (filled ones always show).
    @Binding var added: Set<PaperField>
    let hints: [PaperField: PaperFieldHint]
    let phoneHints: [PaperPhoneRow.ID: PaperFieldHint]
    var focus: FocusState<PaperFocus?>.Binding

    /// Order of the non-phone rows.
    static let fieldOrder: [PaperField] = [.telegram, .whatsapp, .instagram, .email, .website, .linkedin, .address]

    private enum Row: Hashable, Identifiable {
        case phone(PaperPhoneRow.ID)
        case field(PaperField)
        var id: Self { self }
    }

    private var rows: [Row] {
        details.phones.map { .phone($0.id) }
            + Self.fieldOrder.filter { added.contains($0) || !details[$0].isEmpty }.map(Row.field)
    }

    var body: some View {
        Section {
            ForEach(rows) { row in
                switch row {
                case .phone(let id):
                    if let binding = phoneBinding(id) {
                        PaperPhoneRowView(row: binding, hint: phoneHints[id], focus: focus, isFocused: focus.wrappedValue == .phone(id))
                    }
                case .field(let field):
                    PaperContactFieldRow(field: field, text: typed(field), hint: hints[field], focus: focus,
                                         isFocused: focus.wrappedValue == .field(field))
                }
            }
            .onDelete { offsets in
                let current = rows
                withAnimation {
                    for index in offsets { delete(current[index]) }
                }
            }

            AddContactMenu(isEnabled: rows.count < ContactEntry.maxCount, action: add)
        } header: {
            Text("Contact Info")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if details.phones.filter({ !$0.isEmpty }).count > 1 {
                    Text("The first mobile number is saved as the main one.")
                }
                Text("Read on your iPhone. Check the details before saving.")
            }
        }
        .onChange(of: focus.wrappedValue) { old, _ in
            if let old { leave(old) }
        }
    }

    private func phoneBinding(_ id: PaperPhoneRow.ID) -> Binding<PaperPhoneRow>? {
        guard details.phones.contains(where: { $0.id == id }) else { return nil }
        return Binding {
            details.phones.first { $0.id == id } ?? PaperPhoneRow(label: .mobile, value: "")
        } set: { row in
            guard let index = details.phones.firstIndex(where: { $0.id == id }) else { return }
            var cleaned = row
            cleaned.value = String(ContactFieldInput.typing(row.value, for: .phone).prefix(ContactEntry.maxLength(for: .phone)))
            details.phones[index] = cleaned
        }
    }

    private func typed(_ field: PaperField) -> Binding<String> {
        Binding { details[field] } set: { text in
            guard let kind = field.kind else { details[field] = text; return }
            details[field] = String(ContactFieldInput.typing(text, for: kind).prefix(ContactEntry.maxLength(for: kind)))
        }
    }

    /// A number goes to an empty number row when there is one; any other kind shows its row (or the one
    /// already there) and takes the keyboard there.
    private func add(_ kind: ContactFieldKind) {
        let target: PaperFocus
        if kind == .phone {
            target = .phone(details.phones.first(where: \.isEmpty)?.id ?? details.addPhone())
        } else {
            let field = PaperField(kind: kind)
            added.insert(field)
            target = .field(field)
        }
        Task { focus.wrappedValue = target }
    }

    private func delete(_ row: Row) {
        switch row {
        case .phone(let id): details.phones.removeAll { $0.id == id }
        case .field(let field):
            details[field] = ""
            added.remove(field)
        }
    }

    /// Leaving a row: clean the value up; a row left empty goes away.
    private func leave(_ focus: PaperFocus) {
        switch focus {
        case .phone(let id):
            guard let index = details.phones.firstIndex(where: { $0.id == id }) else { return }
            let value = ContactFieldInput.normalized(details.phones[index].value, for: .phone)
            if value.isEmpty { details.phones.remove(at: index) } else { details.phones[index].value = value }
        case .field(let field):
            guard let kind = field.kind else { return }
            let value = ContactFieldInput.normalized(details[field], for: kind)
            details[field] = value
            if value.isEmpty { added.remove(field) }
        }
    }
}

struct PaperPhoneRowView: View {
    @Binding var row: PaperPhoneRow
    let hint: PaperFieldHint?
    var focus: FocusState<PaperFocus?>.Binding
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperContactRowLayout(symbolName: row.label.symbolName, tint: ContactFieldKind.phone.tint, hint: hint) {
                Menu {
                    Picker("Label", selection: $row.label) {
                        ForEach(PhoneLabel.allCases) { label in
                            Label(label.title, systemImage: label.symbolName).tag(label)
                        }
                    }
                    .pickerStyle(.inline)
                } label: {
                    HStack(spacing: 3) {
                        Text(row.label.title)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                }
                .accessibilityLabel("Phone Label")
                .accessibilityValue(row.label.title)
            } value: {
                TextField("Phone", text: $row.value, prompt: Text(PaperField.phone.placeholder))
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused(focus, equals: .phone(row.id))
                    .accessibilityLabel(row.label.title)
            }
            if !isFocused, let problem = ContactFieldInput.problem(row.value, for: .phone) {
                ContactProblemNote(problem)
            }
        }
    }
}

/// Telegram, WhatsApp, Instagram, email, website, LinkedIn or the address, with the reader's hint.
struct PaperContactFieldRow: View {
    let field: PaperField
    @Binding var text: String
    let hint: PaperFieldHint?
    var focus: FocusState<PaperFocus?>.Binding
    let isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            PaperContactRowLayout(symbolName: field.symbolName, tint: field.tint, hint: hint) {
                Text(field.title)
                    .foregroundStyle(.secondary)
            } value: {
                TextField(field.title, text: $text, prompt: Text(field.placeholder))
                    .textContentType(field.contentType)
                    .keyboardType(field.keyboard)
                    .textInputAutocapitalization(field.capitalizesWords ? .words : .never)
                    .autocorrectionDisabled(!field.capitalizesWords)
                    .submitLabel(.done)
                    .focused(focus, equals: .field(field))
                    .onSubmit { focus.wrappedValue = nil }
                    .accessibilityHint(hint == .guessed ? String(localized: "Guessed from the card’s layout. Check it.") : "")
            }
            if !isFocused, let kind = field.kind, let problem = ContactFieldInput.problem(text, for: kind) {
                ContactProblemNote(problem)
            }
        }
    }
}

/// One contact row: icon, the label on top and the value under it at full width, so long emails and links
/// show whole and every row lines up the same way (like Contacts). A phone's label is its tinted menu.
private struct PaperContactRowLayout<RowLabel: View, Value: View>: View {
    let symbolName: String
    let tint: Color
    let hint: PaperFieldHint?
    @ViewBuilder let label: RowLabel
    @ViewBuilder let value: Value

    var body: some View {
        HStack(spacing: 12) {
            SettingsIcon(symbolName, color: tint)
            VStack(alignment: .leading, spacing: 2) {
                label
                    .font(.subheadline)
                value
            }
            if let hint {
                HintBadge(hint: hint)
            }
        }
    }
}
