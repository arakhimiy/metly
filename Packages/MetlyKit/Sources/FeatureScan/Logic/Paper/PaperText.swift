import Foundation

/// Small text helpers shared by the paper-card heuristics.
nonisolated enum PaperText {
    /// Apostrophes used in Uzbek Latin (o‘, g‘, ʼ) — all count as letters inside a word.
    static let apostrophes: Set<Character> = ["'", "’", "‘", "ʻ", "ʼ", "`"]

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lower-cased words with surrounding punctuation removed ("«Uzum»," → "uzum").
    static func words(_ text: String) -> [String] {
        text.split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "/" })
            .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}«»\"“”„!?|·•-–—")) }
            .filter { !$0.isEmpty }
    }

    static func letterCount(_ text: String) -> Int {
        text.count(where: \.isLetter)
    }

    static func hasDigits(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }

    /// True when every letter is upper-case ("AZIZA KARIMOVA").
    static func isAllCaps(_ text: String) -> Bool {
        let letters = text.filter(\.isLetter)
        return !letters.isEmpty && letters == letters.uppercased() && letters != letters.lowercased()
    }

    /// "AZIZA KARIMOVA" → "Aziza Karimova", "ABDUG'ANIYEV" → "Abdug'aniyev", "HEAD OF SALES" → "Head of Sales";
    /// acronyms ("CTO", "VP") and mixed-case text are kept as written.
    static func titleCasedIfAllCaps(_ text: String) -> String {
        guard isAllCaps(text) else { return text }
        return text.split(separator: " ", omittingEmptySubsequences: true)
            .enumerated()
            .map { offset, word in
                let lower = word.lowercased()
                if acronyms.contains(lower) { return String(word) }
                if offset > 0, smallWords.contains(lower) { return lower }
                return lower.split(separator: "-", omittingEmptySubsequences: false)
                    .map { part in part.prefix(1).uppercased() + part.dropFirst() }
                    .joined(separator: "-")
            }
            .joined(separator: " ")
    }

    private static let acronyms: Set<String> = [
        "ceo", "cto", "cfo", "coo", "cmo", "cpo", "cio", "chro", "vp", "svp", "evp", "hr", "qa", "ux", "ui", "pm",
        "it", "ai", "ml", "pr", "smm", "seo", "r&d", "ux/ui", "ui/ux",
    ]

    private static let smallWords: Set<String> = ["of", "and", "at", "for", "the", "in", "&", "и", "по", "va"]

    /// Strips separators and stray punctuation left after values were removed from a line.
    static func cleanLeftover(_ text: String) -> String {
        collapseWhitespace(text).trimmingCharacters(in: CharacterSet(charactersIn: " ,;:|/\\-–—•·()[]+"))
    }
}
