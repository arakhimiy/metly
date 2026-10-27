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
    /// English prefix of names saved before localization (and in English).
    private static let englishPrefix = "Someone"

    /// "Someone at Tashkent Tech Week" / "Someone You Met" (localized — it is the person's visible name).
    static func placeholder(eventName: String?) -> String {
        if let eventName, !eventName.trimmingCharacters(in: .whitespaces).isEmpty {
            return String(localized: "Someone at \(eventName)", comment: "Name for a person saved without a name; %@ is the event")
        }
        return String(localized: "Someone You Met", comment: "Name for a person saved without a name")
    }

    static func isPlaceholder(_ fullName: String) -> Bool {
        if fullName.hasPrefix(englishPrefix + " ") || fullName == placeholder(eventName: nil) { return true }
        // The current language's "Someone at %@": match the text around the event name.
        let marker = "\u{1}"
        let parts = placeholder(eventName: marker).components(separatedBy: marker)
        guard parts.count == 2, !(parts[0] + parts[1]).trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return fullName.count > parts[0].count + parts[1].count && fullName.hasPrefix(parts[0]) && fullName.hasSuffix(parts[1])
    }
}
