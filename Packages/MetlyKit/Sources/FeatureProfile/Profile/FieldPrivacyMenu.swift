import MetlyCore
import SwiftUI

/// MENU_FIELD_PRIVACY — ✓ Public (Anyone with your link) · Connections · Private.
struct FieldPrivacyMenu: View {
    let kind: ContactFieldKind
    @Binding var privacy: FieldPrivacy

    var body: some View {
        Menu {
            Section("Who Can See Your \(kind.title)") {
                Picker("Privacy", selection: $privacy) {
                    ForEach(FieldPrivacy.allCases) { option in
                        Label {
                            Text(option.title)
                            Text(option.explanation)
                        } icon: {
                            Image(systemName: option.symbolName)
                        }
                        .tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            ViewThatFits(in: .horizontal) {
                PrivacyBadge(privacy: privacy, showsTitle: true)
                PrivacyBadge(privacy: privacy, showsTitle: false)
            }
        }
        .sensoryFeedback(.selection, trigger: privacy)
        .accessibilityLabel("\(kind.title) Privacy")
        .accessibilityValue(privacy.title)
        .accessibilityHint(privacy.explanation)
    }
}

/// Compact tinted "􀆪 Public ⌃⌄" label for the privacy menu.
private struct PrivacyBadge: View {
    let privacy: FieldPrivacy
    let showsTitle: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: privacy.symbolName)
            if showsTitle {
                Text(privacy.title)
                    .lineLimit(1)
            }
            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .font(.subheadline)
        .fixedSize()
        .frame(minHeight: 44)
        .contentShape(.rect)
    }
}
