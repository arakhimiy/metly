import Foundation

/// Card names: create-wizard suggestions and "{name} Copy" for duplicates.
nonisolated enum CardNaming {
    /// Quick picks on the Details step.
    static let suggestions = [
        String(localized: "Work", comment: "Suggested card name"),
        String(localized: "Personal", comment: "Suggested card name"),
        String(localized: "Conference", comment: "Suggested card name"),
    ]

    /// Suffix of duplicated card names ("Work Copy").
    /// Own key: the "Copy" button (a verb) translates differently.
    static var copyWord: String {
        String(localized: "Copy (card name suffix)", defaultValue: "Copy", comment: "Noun appended to a duplicated card name: “Work Copy”")
    }

    /// First suggestion not used yet, else "Card {n}".
    static func defaultName(existing: [String]) -> String {
        let used = Set(existing.map { $0.lowercased() })
        if let free = suggestions.first(where: { !used.contains($0.lowercased()) }) { return free }
        var number = existing.count + 1
        while used.contains(numberedName(number).lowercased()) { number += 1 }
        return numberedName(number)
    }

    /// "Work" → "Work Copy" → "Work Copy 2"…; duplicating "Work Copy" gives "Work Copy 2", not "Work Copy Copy".
    static func copyName(for name: String, existing: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseName(of: trimmed.isEmpty ? String(localized: "Card") : trimmed)
        let used = Set(existing.map { $0.lowercased() })
        let first = "\(base) \(copyWord)"
        if !used.contains(first.lowercased()) { return first }
        var number = 2
        while used.contains("\(first) \(number)".lowercased()) { number += 1 }
        return "\(first) \(number)"
    }

    private static func numberedName(_ number: Int) -> String {
        String(localized: "Card \(number)", comment: "Default card name when every suggestion is taken")
    }

    /// Strips a trailing " Copy" / " Copy {n}" (English or the current language).
    private static func baseName(of name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        let copyWords: Set<String> = ["Copy", copyWord]
        if let last = words.last, Int(last) != nil, words.count >= 3, copyWords.contains(words[words.count - 2]) {
            words.removeLast(2)
        } else if words.count >= 2, let last = words.last, copyWords.contains(last) {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }
}
