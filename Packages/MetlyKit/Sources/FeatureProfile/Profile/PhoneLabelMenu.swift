import MetlyCardKit
import MetlyCore
import SwiftUI

/// The tappable label above a phone number ("Mobile ⌃⌄"): ✓ Mobile · Work · Home · Other.
struct PhoneLabelMenu: View {
    @Binding var label: PhoneLabel

    var body: some View {
        Menu {
            Picker("Label", selection: $label) {
                ForEach(PhoneLabel.allCases) { option in
                    Label(option.title, systemImage: option.symbolName)
                        .tag(option)
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 3) {
                Text(label.title)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .imageScale(.small)
            }
            .font(.subheadline)
            .foregroundStyle(.tint)
            // A larger tap area than the small title it looks like, without moving the number below.
            .padding(.vertical, 6)
            .padding(.trailing, 16)
            .contentShape(.rect)
            .padding(.vertical, -6)
            .padding(.trailing, -16)
        }
        .sensoryFeedback(.selection, trigger: label)
        .accessibilityLabel("Phone Label")
        .accessibilityValue(label.phoneNumberTitle)
    }
}

extension PhoneLabel {
    /// Filled glyph for the row's settings tile (matches `phone.fill`, `envelope.fill`…).
    var tileSymbolName: String {
        switch self {
        case .mobile: "iphone"
        case .work: "building.2.fill"
        case .home: "house.fill"
        case .other: "phone.fill"
        }
    }
}
