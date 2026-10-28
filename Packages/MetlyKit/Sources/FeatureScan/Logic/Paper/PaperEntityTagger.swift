import Foundation
import NaturalLanguage

/// A named-entity hint from `NLTagger` (`.nameType`).
nonisolated enum PaperEntity: Equatable, Sendable {
    case person
    case organization
}

/// Runs `NLTagger` `.nameType` over the candidate lines (joined, so the tagger sees the whole card)
/// and reports which lines are mostly a personal name or an organisation. It is one signal
/// among many: the tagger knows English names well and Uzbek ones hardly at all.
nonisolated enum PaperEntityTagger {
    static func entities(for texts: [String]) -> [String: PaperEntity] {
        var seen = Set<String>()
        let unique = texts.filter { !$0.isEmpty && seen.insert($0).inserted }
        guard !unique.isEmpty else { return [:] }
        let joined = unique.joined(separator: "\n")
        var lineRanges: [(Range<String.Index>, String)] = []
        var start = joined.startIndex
        for text in unique {
            let end = joined.index(start, offsetBy: text.count)
            lineRanges.append((start..<end, text))
            start = end < joined.endIndex ? joined.index(after: end) : end
        }

        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = joined
        var personLetters: [String: Int] = [:]
        var organizationLetters: [String: Int] = [:]
        tagger.enumerateTags(in: joined.startIndex..<joined.endIndex, unit: .word, scheme: .nameType,
                             options: [.omitPunctuation, .omitWhitespace, .joinNames]) { tag, range in
            guard let tag, tag == .personalName || tag == .organizationName,
                  let line = lineRanges.first(where: { $0.0.contains(range.lowerBound) })?.1 else { return true }
            let letters = joined[range].count(where: \.isLetter)
            if tag == .personalName { personLetters[line, default: 0] += letters } else { organizationLetters[line, default: 0] += letters }
            return true
        }

        var result: [String: PaperEntity] = [:]
        for text in unique {
            let total = max(1, PaperText.letterCount(text))
            if Double(personLetters[text] ?? 0) / Double(total) >= 0.6 {
                result[text] = .person
            } else if Double(organizationLetters[text] ?? 0) / Double(total) >= 0.5 {
                result[text] = .organization
            }
        }
        return result
    }
}
