import Foundation

/// Card names: create-wizard suggestions and "{name} Copy" for duplicates.
nonisolated enum CardNaming {
    /// Quick picks on the Details step.
    static let suggestions = ["Work", "Personal", "Conference"]

    /// First suggestion not used yet, else "Card {n}".
    static func defaultName(existing: [String]) -> String {
        let used = Set(existing.map { $0.lowercased() })
        if let free = suggestions.first(where: { !used.contains($0.lowercased()) }) { return free }
        var number = existing.count + 1
        while used.contains("card \(number)") { number += 1 }
        return "Card \(number)"
    }

    /// "Work" → "Work Copy" → "Work Copy 2"…; duplicating "Work Copy" gives "Work Copy 2", not "Work Copy Copy".
    static func copyName(for name: String, existing: [String]) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = baseName(of: trimmed.isEmpty ? "Card" : trimmed)
        let used = Set(existing.map { $0.lowercased() })
        let first = "\(base) Copy"
        if !used.contains(first.lowercased()) { return first }
        var number = 2
        while used.contains("\(first) \(number)".lowercased()) { number += 1 }
        return "\(first) \(number)"
    }

    /// Strips a trailing " Copy" / " Copy {n}".
    private static func baseName(of name: String) -> String {
        var words = name.split(separator: " ").map(String.init)
        if let last = words.last, Int(last) != nil, words.count >= 3, words[words.count - 2] == "Copy" {
            words.removeLast(2)
        } else if words.count >= 2, words.last == "Copy" {
            words.removeLast()
        }
        return words.joined(separator: " ")
    }
}
