import MetlyDesign
import SwiftUI

/// Which PAPER_REVIEW text field has focus.
enum PaperFocus: Hashable {
    case field(PaperField)
    case phone(PaperPhoneRow.ID)
}

/// "Detected Details": name, title and company, with a hint on values read from the card and
/// a one-tap **Swap Name and Company** for cards that put the brand where the name usually is.
struct PaperDetailsSection: View {
    @Binding var details: PaperCardDetails
    let hints: [PaperField: PaperFieldHint]
    var focus: FocusState<PaperFocus?>.Binding
    let onSwap: () -> Void
    /// Read off a photo ("Detected Details"); false for a contact typed in by hand ("Details").
    var wasRead = true

    var body: some View {
        Section {
            ForEach(PaperRoles.fields) { field in
                PaperFieldRow(field: field, text: $details[field], hint: hints[field], focus: focus) {
                    focus.wrappedValue = next(after: field)
                }
            }
            if details.canSwapNameAndCompany {
                Button("Swap Name and Company", systemImage: "arrow.up.arrow.down", action: onSwap)
            }
        } header: {
            Text(wasRead ? "Detected Details" : "Details")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                if PaperRoles.fields.contains(where: { hints[$0] == .guessed }) {
                    Text("\(Image(systemName: "questionmark.circle.fill")) Guessed from the card’s layout.")
                }
                if !details.canSave {
                    Text("Add a name to save.")
                }
            }
        }
    }

    private func next(after field: PaperField) -> PaperFocus? {
        switch field {
        case .name: .field(.title)
        case .title: .field(.company)
        default: details.phones.first.map { .phone($0.id) }
        }
    }
}

struct PaperFieldRow: View {
    let field: PaperField
    @Binding var text: String
    let hint: PaperFieldHint?
    var focus: FocusState<PaperFocus?>.Binding
    let onSubmit: () -> Void

    var body: some View {
        LabeledContent {
            HStack(spacing: 8) {
                TextField(field.title, text: $text, prompt: Text(field.placeholder))
                    .multilineTextAlignment(.trailing)
                    .textContentType(field.contentType)
                    .keyboardType(field.keyboard)
                    .textInputAutocapitalization(field.capitalizesWords ? .words : .never)
                    .autocorrectionDisabled(!field.capitalizesWords)
                    .submitLabel(field == .linkedin ? .done : .next)
                    .focused(focus, equals: .field(field))
                    .onSubmit(onSubmit)
                    .accessibilityHint(hint == .guessed ? String(localized: "Guessed from the card’s layout. Check it.", bundle: .appStrings) : "")
                if let hint {
                    HintBadge(hint: hint)
                }
            }
        } label: {
            Label {
                Text(field.title)
            } icon: {
                SettingsIcon(field.symbolName, color: field.tint)
            }
        }
    }
}

extension PaperField {
    var tint: Color {
        switch self {
        case .name: .teal
        case .title: .orange
        case .company: .purple
        default: kind?.tint ?? .gray
        }
    }
}

/// ✓ detected format or strong evidence · ? guessed from layout. Decorative for VoiceOver (the field's hint says it).
struct HintBadge: View {
    let hint: PaperFieldHint

    var body: some View {
        Image(systemName: hint == .detected ? "checkmark.circle.fill" : "questionmark.circle.fill")
            .foregroundStyle(hint == .detected ? Color.green : Color.orange)
            .imageScale(.small)
            .accessibilityHidden(true)
    }
}
