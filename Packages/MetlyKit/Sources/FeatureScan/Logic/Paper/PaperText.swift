import Foundation

/// Small text helpers shared by the paper-card heuristics.
nonisolated enum PaperText {
    /// Apostrophes used in Uzbek Latin (o‘, g‘, ʼ) — all count as letters inside a word.
    static let apostrophes: Set<Character> = ["'", "’", "‘", "ʻ", "ʼ", "`", "´"]

    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Every Uzbek apostrophe variant as a plain "'".
    static func unifyingApostrophes(_ text: String) -> String {
        String(text.map { apostrophes.contains($0) ? "'" : $0 })
    }

    /// Lower-cased words with surrounding punctuation removed ("«Uzum»," → "uzum", "O‘g‘li" → "o'g'li").
    static func words(_ text: String) -> [String] {
        unifyingApostrophes(text)
            .split(whereSeparator: { $0.isWhitespace || $0 == "," || $0 == "/" })
            .map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}«»\"“”„!?|·•-–—'")) }
            .filter { !$0.isEmpty }
    }

    /// Words, with hyphenated ones also split ("арт-директор" → "арт-директор", "арт", "директор").
    static func wordsAndParts(_ text: String) -> [String] {
        words(text).flatMap { word in
            word.contains("-") ? [word] + word.split(separator: "-").map(String.init) : [word]
        }
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

    // MARK: Comparing

    /// Lower-case, apostrophes unified, Cyrillic transliterated, only letters / digits / single spaces.
    /// "ООО «Узум Маркет»" → "ooo uzum market", "O‘zbekiston" → "o'zbekiston".
    static func comparable(_ text: String) -> String {
        let latin = transliterated(unifyingApostrophes(text).lowercased())
        let kept = latin.map { $0.isLetter || $0.isNumber || $0 == "'" ? $0 : " " }
        return collapseWhitespace(String(kept))
    }

    /// Letters only, transliterated ("Najot Ta'lim" → "najottalim") — compared with domain names.
    static func letters(_ text: String) -> String {
        transliterated(text.lowercased()).filter { $0.isLetter && $0.isASCII }
    }

    /// Russian / Uzbek Cyrillic → Latin, close to how brands write their domains.
    static func transliterated(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for character in text {
            if let latin = cyrillic[character] { result += latin } else { result.append(character) }
        }
        return result
    }

    private static let cyrillic: [Character: String] = [
        "а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "j", "з": "z", "и": "i",
        "й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t",
        "у": "u", "ф": "f", "х": "x", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "sh", "ъ": "", "ы": "i", "ь": "",
        "э": "e", "ю": "yu", "я": "ya", "ў": "o'", "қ": "q", "ғ": "g'", "ҳ": "h",
    ]

    /// 0…1, 1 = identical (Levenshtein distance relative to the longer string).
    static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let a = Array(lhs), b = Array(rhs)
        guard !a.isEmpty || !b.isEmpty else { return 1 }
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return 1 - Double(previous[b.count]) / Double(max(a.count, b.count))
    }
}
