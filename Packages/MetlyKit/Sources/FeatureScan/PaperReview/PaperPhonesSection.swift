import MetlyCore
import MetlyDesign
import SwiftUI

/// "Phone": every number on the card with its label (Mobile / Work / Home / Other), like Contacts.
/// Swipe to delete; **Add Phone** for one the camera missed. The first mobile is saved as the main number.
struct PaperPhonesSection: View {
    @Binding var details: PaperCardDetails
    let hints: [PaperPhoneRow.ID: PaperFieldHint]
    var focus: FocusState<PaperFocus?>.Binding

    var body: some View {
        Section {
            ForEach($details.phones) { $row in
                PaperPhoneRowView(row: $row, hint: hints[row.id], focus: focus, onSubmit: { submit(from: row.id) })
            }
            .onDelete { details.removePhones(at: $0) }

            Button("Add Phone", systemImage: "plus.circle.fill", action: addPhone)
        } header: {
            Text("Phone")
        } footer: {
            if details.phones.filter({ !$0.isEmpty }).count > 1 {
                Text("The first mobile number is saved as the main one.")
            }
        }
    }

    private func addPhone() {
        withAnimation {
            focus.wrappedValue = .phone(details.addPhone())
        }
    }

    private func submit(from id: PaperPhoneRow.ID) {
        guard let index = details.phones.firstIndex(where: { $0.id == id }) else { return }
        focus.wrappedValue = index + 1 < details.phones.count ? .phone(details.phones[index + 1].id) : .field(.email)
    }
}

private struct PaperPhoneRowView: View {
    @Binding var row: PaperPhoneRow
    let hint: PaperFieldHint?
    var focus: FocusState<PaperFocus?>.Binding
    let onSubmit: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            Picker("Label", selection: $row.label) {
                ForEach(PhoneLabel.allCases) { label in
                    Label(label.title, systemImage: label.symbolName).tag(label)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("Phone Label")

            HStack(spacing: 8) {
                TextField("Phone", text: $row.value, prompt: Text(PaperField.phone.placeholder))
                    .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
                    .textContentType(.telephoneNumber)
                    .keyboardType(.phonePad)
                    .focused(focus, equals: .phone(row.id))
                    .onSubmit(onSubmit)
                    .accessibilityLabel(row.label.title)
                if let hint {
                    HintBadge(hint: hint)
                }
            }
        }
    }
}
