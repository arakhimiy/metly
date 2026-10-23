import Foundation
import MetlyCore
import MetlyDesign
import UIKit

/// Input + privacy helpers for the owner's contact fields (PROFILE · Contact Details).
nonisolated enum ContactFieldRules {
    // Input rules are shared with card creation (MetlyDesign.ContactFieldInput).
    static func placeholder(for kind: ContactFieldKind) -> String { ContactFieldInput.placeholder(for: kind) }
    static func keyboardType(for kind: ContactFieldKind) -> UIKeyboardType { ContactFieldInput.keyboardType(for: kind) }
    static func contentType(for kind: ContactFieldKind) -> UITextContentType? { ContactFieldInput.contentType(for: kind) }
    static func normalized(_ value: String, for kind: ContactFieldKind) -> String { ContactFieldInput.normalized(value, for: kind) }

    /// Fields with a value that the audience may see, in display order (Private never qualifies).
    static func visibleFields(_ fields: [ContactField], to audience: CardAudience) -> [ContactField] {
        let order = ContactFieldKind.allCases
        return fields
            .filter { !$0.isEmpty && audience.allows($0.privacy) }
            .sorted { (order.firstIndex(of: $0.kind) ?? 0) < (order.firstIndex(of: $1.kind) ?? 0) }
    }

    /// Number of filled fields per privacy level.
    static func privacyCounts(_ fields: [ContactField]) -> [FieldPrivacy: Int] {
        var counts: [FieldPrivacy: Int] = [:]
        for field in fields where !field.isEmpty {
            counts[field.privacy, default: 0] += 1
        }
        return counts
    }
}

nonisolated extension FieldPrivacy {
    /// SF Symbol shown in the privacy menu.
    var symbolName: String {
        switch self {
        case .public: "globe"
        case .connections: "person.2.fill"
        case .private: "lock.fill"
        }
    }
}
