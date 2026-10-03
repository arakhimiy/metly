import MetlyCore
import SwiftUI

/// Small capsule naming a field's privacy level (Public / Connections / Private).
struct PrivacyBadge: View {
    let privacy: FieldPrivacy

    var body: some View {
        Label(privacy.title, systemImage: privacy.symbolName)
            .labelStyle(.titleAndIcon)
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
