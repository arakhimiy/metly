import Foundation
import MetlyCore
import UIKit

/// How a contact field is typed and cleaned up — shared by PROFILE · Contact Details and the
/// inline value entry in "Show on This Card".
public nonisolated enum ContactFieldInput {
    /// Longest value the server accepts.
    public static let maxLength = 200

    public static func placeholder(for kind: ContactFieldKind) -> String {
        switch kind {
        case .phone: "+998 90 123 45 67"
        case .email: "name@example.com"
        case .telegram: "@username"
        case .website: "yoursite.com"
        case .linkedin: "in/username"
        case .whatsapp: "+998 90 123 45 67"
        case .instagram: "@username"
        }
    }

    public static func keyboardType(for kind: ContactFieldKind) -> UIKeyboardType {
        switch kind {
        case .phone, .whatsapp: .phonePad
        case .email: .emailAddress
        case .telegram, .instagram: .twitter
        case .website, .linkedin: .URL
        }
    }

    public static func contentType(for kind: ContactFieldKind) -> UITextContentType? {
        switch kind {
        case .phone, .whatsapp: .telephoneNumber
        case .email: .emailAddress
        case .website, .linkedin: .URL
        case .telegram, .instagram: nil
        }
    }

    /// Cleans a value when the user leaves the field (never while typing).
    public static func normalized(_ value: String, for kind: ContactFieldKind) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        switch kind {
        case .phone, .whatsapp:
            result = strippingPrefixes(["https://wa.me/", "http://wa.me/", "wa.me/"], from: result)
            result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        case .email:
            result = result.lowercased()
        case .telegram:
            result = strippingPrefixes(["https://", "http://"], from: result)
            result = strippingPrefixes(["t.me/", "telegram.me/"], from: result)
            result = trimmingTrailingSlashes(result)
            if !result.hasPrefix("@") { result = "@" + result }
        case .instagram:
            result = strippingPrefixes(["https://", "http://"], from: result)
            result = strippingPrefixes(["www."], from: result)
            result = strippingPrefixes(["instagram.com/", "instagr.am/"], from: result)
            result = trimmingTrailingSlashes(result)
            if let query = result.firstIndex(of: "?") { result = String(result[..<query]) }
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
