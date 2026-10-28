import MetlyCardKit
import MetlyCore
import MetlyDesign
import SwiftUI

/// "Show on This Card" row for several numbers: one switch for all of them (CARD_EDITOR › Fields).
///
/// Lists every filled number as "{number} · {label} · {privacy}" and notes the Private ones, which
/// never appear on a card. The switch is disabled only when every number is Private.
struct CardPhonesToggleRow: View {
    /// Filled numbers, primary first.
    let phones: [LabeledPhone]
    @Binding var isOn: Bool
    let privateCount: Int

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: 12) {
                SettingsIcon(field: .phone)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Phone Numbers")
                    ForEach(phones) { phone in
                        Text(verbatim: "\(phone.value) · \(phone.label.title) · \(phone.privacy.title)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    if privateCount > 0 {
                        Label(privateNote, systemImage: "lock.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(spokenLabel))
        }
        .disabled(allPrivate)
    }

    private var allPrivate: Bool { !phones.isEmpty && privateCount == phones.count }

    private var privateNote: String {
        allPrivate
            ? String(localized: "Private — hidden from all cards")
            : String(localized: "Private numbers never appear on a card.")
    }

    /// "Phone Numbers. Mobile phone, +998…, Public. Home phone, +998…, Private, hidden from all cards."
    private var spokenLabel: String {
        let numbers = phones.map { phone in
            phone.privacy == .private
                ? String(localized: "\(phone.label.phoneNumberTitle), \(phone.value), private, hidden from all cards")
                : "\(phone.label.phoneNumberTitle), \(phone.value), \(phone.privacy.title)"
        }
        return ([String(localized: "Phone Numbers")] + numbers).joined(separator: ". ")
    }
}

#Preview("Phone Numbers row") {
    @Previewable @State var isOn = true
    Form {
        CardPhonesToggleRow(phones: [
            LabeledPhone(id: LabeledPhone.primaryID, label: .mobile, value: "+998 90 123 45 67", privacy: .public),
            LabeledPhone(label: .work, value: "+998 71 200 10 20", privacy: .connections),
            LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .private),
        ], isOn: $isOn, privateCount: 1)
        CardPhonesToggleRow(phones: [
            LabeledPhone(id: LabeledPhone.primaryID, label: .mobile, value: "+998 90 123 45 67", privacy: .private),
            LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .private),
        ], isOn: .constant(false), privateCount: 2)
    }
}
