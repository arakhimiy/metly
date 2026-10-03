import Foundation
import MetlyCore
import UIKit

/// Input + privacy helpers for the owner's contact fields (PROFILE · Contact Details).
nonisolated enum ContactFieldRules {
    static func placeholder(for kind: ContactFieldKind) -> String {
        switch kind {
        case .phone: "+998 90 123 45 67"
        case .email: "name@example.com"
        case .telegram: "@username"
        case .website: "yoursite.com"
        case .linkedin: "in/username"
        }
    }

    static func keyboardType(for kind: ContactFieldKind) -> UIKeyboardType {
        switch kind {
        case .phone: .phonePad
        case .email: .emailAddress
        case .telegram: .twitter
        case .website, .linkedin: .URL
        }
    }

    static func contentType(for kind: ContactFieldKind) -> UITextContentType? {
        switch kind {
        case .phone: .telephoneNumber
        case .email: .emailAddress
        case .website, .linkedin: .URL
        case .telegram: nil
        }
    }

    /// Cleans a value when the user leaves the field (never while typing).
    static func normalized(_ value: String, for kind: ContactFieldKind) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        switch kind {
        case .phone:
            result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .email:
            result = result.lowercased()
        case .telegram:
            result = strippingPrefixes(["https://", "http://"], from: result)
            result = strippingPrefixes(["t.me/", "telegram.me/"], from: result)
            result = trimmingTrailingSlashes(result)
            if !result.hasPrefix("@") { result = "@" + result }
        case .website:
            result = trimmingTrailingSlashes(strippingPrefixes(["https://", "http://"], from: result))
        case .linkedin:
            result = strippingPrefixes(["https://", "http://"], from: result)
            result = strippingPrefixes(["www."], from: result)
            result = strippingPrefixes(["linkedin.com/"], from: result)
            result = trimmingTrailingSlashes(result)
        }
        return result
    }

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

    private static func strippingPrefixes(_ prefixes: [String], from value: String) -> String {
        for prefix in prefixes where value.lowercased().hasPrefix(prefix) {
            return String(value.dropFirst(prefix.count))
        }
        return value
    }

    private static func trimmingTrailingSlashes(_ value: String) -> String {
        var result = value
        while result.hasSuffix("/") { result.removeLast() }
        return result
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
