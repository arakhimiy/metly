import MetlyDesign
import SwiftUI

/// "Detected Details": every field editable, with a hint on values read from the card.
struct PaperDetailsSection: View {
    @Binding var details: PaperCardDetails
    let hints: [PaperField: PaperFieldHint]
    var focusedField: FocusState<PaperField?>.Binding

    var body: some View {
        Section {
            ForEach(PaperField.allCases) { field in
                PaperFieldRow(field: field, text: $details[field], hint: hints[field],
                              focusedField: focusedField, onSubmit: { focusNext(after: field) })
            }
        } header: {
            Text("Detected Details")
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text("Read on your iPhone. Check the details before saving.")
                if hints.values.contains(.guessed) {
                    Text("\(Image(systemName: "questionmark.circle.fill")) Guessed from the card’s layout.")
                }
                if !details.canSave {
                    Text("Add a name to save.")
                }
            }
        }
    }

    private func focusNext(after field: PaperField) {
        let all = PaperField.allCases
        guard let index = all.firstIndex(of: field), index + 1 < all.count else {
            focusedField.wrappedValue = nil
            return
        }
        focusedField.wrappedValue = all[index + 1]
    }
}

private struct PaperFieldRow: View {
    let field: PaperField
    @Binding var text: String
    let hint: PaperFieldHint?
    var focusedField: FocusState<PaperField?>.Binding
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
                    .submitLabel(field == PaperField.allCases.last ? .done : .next)
                    .focused(focusedField, equals: field)
                    .onSubmit(onSubmit)
                    .accessibilityHint(hint == .guessed ? "Guessed from the card’s layout. Check it." : "")
                if let hint {
                    HintBadge(hint: hint)
                }
            }
        } label: {
            Label {
                Text(field.title)
            } icon: {
                SettingsIcon(field.symbolName, color: tint)
            }
        }
    }

    private var tint: Color {
        switch field {
        case .name: .teal
        case .title: .orange
        case .company: .purple
        default: field.kind?.tint ?? .gray
        }
    }
}

/// ✓ detected format · ? guessed from layout. Decorative for VoiceOver (the field's hint says it).
private struct HintBadge: View {
    let hint: PaperFieldHint

    var body: some View {
        Image(systemName: hint == .detected ? "checkmark.circle.fill" : "questionmark.circle.fill")
            .foregroundStyle(hint == .detected ? Color.green : Color.orange)
            .imageScale(.small)
            .accessibilityHidden(true)
    }
}
