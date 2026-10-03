import Foundation

/// Name helpers used across People screens.
enum PersonName {
    /// "Kamila Yusupova" → "Kamila".
    static func first(_ fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// Case- and diacritic-insensitive first-name comparison (share-back merge matching).
    static func firstNamesMatch(_ lhs: String, _ rhs: String) -> Bool {
        let a = first(lhs)
        let b = first(rhs)
        guard !a.isEmpty, !b.isEmpty else { return false }
        return a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }
}

/// Names for "Who did you just meet?" records saved without a name.
enum JustMetNaming {
    private static let prefix = "Someone"

    /// "Someone at Tashkent Tech Week" / "Someone You Met".
    static func placeholder(eventName: String?) -> String {
        if let eventName, !eventName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(prefix) at \(eventName)"
        }
        return "\(prefix) You Met"
    }

    static func isPlaceholder(_ fullName: String) -> Bool {
        fullName.hasPrefix(prefix + " ")
    }
}
