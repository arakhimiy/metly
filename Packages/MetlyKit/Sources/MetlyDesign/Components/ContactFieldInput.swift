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
        case .address: String(localized: "Street, building, city")
        }
    }

    public static func keyboardType(for kind: ContactFieldKind) -> UIKeyboardType {
        switch kind {
        case .phone, .whatsapp: .phonePad
        case .email: .emailAddress
        case .telegram, .instagram: .twitter
        case .website, .linkedin: .URL
        case .address: .default
        }
    }

    public static func contentType(for kind: ContactFieldKind) -> UITextContentType? {
        switch kind {
        case .phone, .whatsapp: .telephoneNumber
        case .email: .emailAddress
        case .website, .linkedin: .URL
        case .telegram, .instagram: nil
        case .address: .fullStreetAddress
        }
    }

    /// The value as it's typed: phone numbers spaced for their country (`+998 90 123 45 67`), characters a
    /// kind can't contain dropped (spaces in an email or link; anything but letters, digits, "_" and "." in a
    /// username — a pasted t.me / instagram.com link becomes the username).
    public static func typing(_ value: String, for kind: ContactFieldKind) -> String {
        switch kind {
        case .phone, .whatsapp:
            let lower = value.lowercased()
            if lower.contains("wa.me/") { return PhoneNumberFormat.asYouType(normalized(value, for: kind)) }
            return PhoneNumberFormat.asYouType(value)
        case .email, .website, .linkedin:
            return value.filter { !$0.isWhitespace }
        case .address:
            return value.replacingOccurrences(of: "\n", with: ", ")
        case .telegram, .instagram:
            if value.contains("/") { return normalized(value, for: kind) }
            let body = value.filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_" || $0 == ".") }
            return value.hasPrefix("@") ? "@" + body : body
        }
    }

    /// The red note under a field whose value isn't valid for its kind (nil when fine or empty).
    public static func problem(_ value: String, for kind: ContactFieldKind) -> String? {
        ContactValidation.problem(value, for: kind)
    }

    /// Cleans a value when the user leaves the field (never while typing).
    public static func normalized(_ value: String, for kind: ContactFieldKind) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !result.isEmpty else { return "" }
        switch kind {
        case .phone, .whatsapp:
            result = PhoneNumberFormat.normalized(strippingPrefixes(["https://wa.me/", "http://wa.me/", "wa.me/"], from: result))
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
        case .address:
            result = result.split(whereSeparator: \.isWhitespace).joined(separator: " ")
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
