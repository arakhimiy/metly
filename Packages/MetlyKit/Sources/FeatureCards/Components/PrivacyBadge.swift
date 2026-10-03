import MetlyCore
import SwiftUI

/// Small capsule naming a field's privacy level (Public / Connections / Private).
struct PrivacyBadge: View {
    let privacy: FieldPrivacy

    var body: some View {
        // An HStack, not a Label: inside list rows a Label's modifiers apply to icon and title separately.
        HStack(spacing: 3) {
            Image(systemName: privacy.symbolName)
                .imageScale(.small)
            Text(privacy.title)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(.fill.tertiary, in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(privacy.title) field"))
    }
}

extension FieldPrivacy {
    var symbolName: String {
        switch self {
        case .public: "globe"
        case .connections: "person.2.fill"
        case .private: "lock.fill"
        }
    }
}
