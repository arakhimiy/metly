import MetlyCore
import SwiftUI

/// MENU_FIELD_PRIVACY — ✓ Public (Anyone with your link) · Connections · Private.
struct FieldPrivacyMenu: View {
    /// Menu header ("Who Can See Your Email").
    let title: String
    /// Spoken name of the field ("Email", "Work phone").
    let fieldName: String
    @Binding var privacy: FieldPrivacy
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(kind: ContactFieldKind, privacy: Binding<FieldPrivacy>) {
        self.init(title: String(localized: "Who Can See Your \(kind.title)", bundle: .appStrings), fieldName: kind.title, privacy: privacy)
    }

    init(title: String, fieldName: String, privacy: Binding<FieldPrivacy>) {
        self.title = title
        self.fieldName = fieldName
        _privacy = privacy
    }

    var body: some View {
        Menu {
            Section(title) {
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
            // Large text: the icon alone, so the number or address beside it isn't cut off.
            if dynamicTypeSize >= .xxLarge {
                PrivacyBadge(privacy: privacy, showsTitle: false)
            } else {
                ViewThatFits(in: .horizontal) {
                    PrivacyBadge(privacy: privacy, showsTitle: true)
                    PrivacyBadge(privacy: privacy, showsTitle: false)
                }
            }
        }
        .sensoryFeedback(.selection, trigger: privacy)
        .accessibilityLabel("\(fieldName) Privacy")
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
