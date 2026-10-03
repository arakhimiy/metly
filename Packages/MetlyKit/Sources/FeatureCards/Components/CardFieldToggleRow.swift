import MetlyCore
import MetlyDesign
import SwiftUI

/// "Show on This Card" row: field icon, name + privacy badge, "{value} · {privacy}" and a switch.
/// Private fields are disabled with "Private — hidden from all cards".
struct CardFieldToggleRow: View {
    let field: ContactField
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                SettingsIcon(field: field.kind)
                VStack(alignment: .leading, spacing: 2) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 6) {
                            Text(field.kind.title)
                            PrivacyBadge(privacy: field.privacy)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(field.kind.title)
                            PrivacyBadge(privacy: field.privacy)
                        }
                    }
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .disabled(field.privacy == .private)
        .accessibilityValue(Text(accessibilityValue))
    }

    private var subtitle: String {
        if field.privacy == .private { return "Private — hidden from all cards" }
        let value = field.isEmpty ? "Not added in Profile" : field.value
        return "\(value) · \(field.privacy.title)"
    }

    private var accessibilityValue: String {
        if field.privacy == .private { return "Private, hidden from all cards" }
        return field.isEmpty ? "Not added in Profile" : field.value
    }
}
