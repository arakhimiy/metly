import Foundation

/// A text line left after contact values were removed — a name, title or company candidate.
nonisolated struct RoleCandidate: Equatable, Sendable {
    var text: String
    /// Reading order on the card.
    var index: Int
    /// Relative text height (0 = unknown).
    var height: Double
}

nonisolated struct PaperRoles: Equatable, Sendable {
    var name = ""
    var title = ""
    var company = ""
}

/// Decides which lines are the person's name, job title and company using keyword lists
/// (English / Russian / Uzbek), name shape (2–4 capitalised words, surname endings, common
/// given names), type size, position and the company's email/website domain.
nonisolated enum PaperRoleClassifier {
    static func classify(_ candidates: [RoleCandidate], domains: [String]) -> PaperRoles {
        var pool = candidates
        var roles = PaperRoles()
        let labels = companyLabels(from: domains)
        let maxHeight = pool.map(\.height).max() ?? 0

        // 1. Name — the best-shaped line.
        var nameIndex: Int?
        if let best = bestCandidate(in: pool, minimum: 4, score: { nameScore(pool[$0], rank: $0, maxHeight: maxHeight, labels: labels) }) {
            roles.name = PaperText.titleCasedIfAllCaps(pool[best].text)
            nameIndex = pool[best].index
            pool.remove(at: best)
        }

        // 2. Title — the line with the most job-title words; "CTO at Payme" also yields the company.
        var splitCompany: String?
        if let best = bestCandidate(in: pool, minimum: 1, score: { titleScore(pool[$0].text) }) {
            let (title, company) = splitTitleAndCompany(pool[best].text)
            roles.title = PaperText.titleCasedIfAllCaps(title)
            splitCompany = company
            pool.remove(at: best)
        }

        // 3. Company — legal form, company noun, quotes or the email/website domain.
        if let best = bestCandidate(in: pool, minimum: 1, score: { companyScore(pool[$0].text, labels: labels) }) {
            roles.company = pool[best].text
            pool.remove(at: best)
        } else if let splitCompany {
            roles.company = splitCompany
        }

        // 4. Layout fallbacks: "Name / Title / Company" is the usual order.
        if roles.title.isEmpty, let nameIndex,
           let next = pool.indices.filter({ pool[$0].index > nameIndex }).min(by: { pool[$0].index < pool[$1].index }),
           looksLikeTitle(pool[next].text) {
            roles.title = PaperText.titleCasedIfAllCaps(pool[next].text)
            pool.remove(at: next)
        }
        if roles.company.isEmpty,
           let first = pool.indices.filter({ looksLikeCompany(pool[$0].text) }).min(by: { pool[$0].index < pool[$1].index }) {
            roles.company = pool[first].text
        }
        return roles
    }

    // MARK: Scores

    static func titleScore(_ text: String) -> Int {
        let words = PaperText.words(text)
        let strong = words.count { word in PaperKeywords.strongTitleStems.contains { word.hasPrefix($0) } }
        let weak = words.count { word in PaperKeywords.weakTitleStems.contains { word.hasPrefix($0) } }
        if strong > 0 { return strong * 2 + weak }
        return weak >= 2 ? weak : 0
    }

    static func companyScore(_ text: String, labels: Set<String>) -> Int {
        let words = PaperText.words(text)
        var score = 0
        if words.contains(where: PaperKeywords.legalForms.contains) { score += 3 }
        if words.contains(where: { word in PaperKeywords.companyStems.contains { word.hasPrefix($0) } }) { score += 2 }
        if text.contains(where: { "«»\"“”„".contains($0) }) { score += 2 }
        if text.contains("&") { score += 1 }
        let letters = text.lowercased().filter { $0.isLetter && $0.isASCII }
        if letters.count >= 3, labels.contains(where: { $0.count >= 3 && (letters.contains($0) || $0.contains(letters)) }) {
            score += 3
        }
        if words.count == 1, PaperText.isAllCaps(text), PaperText.letterCount(text) >= 2 { score += 1 }
        return score
    }

    static func nameScore(_ candidate: RoleCandidate, rank: Int, maxHeight: Double, labels: Set<String>) -> Int {
        let text = candidate.text
        let parts = text.split(separator: " ").map(String.init)
        guard (2...4).contains(parts.count), !PaperText.hasDigits(text), text.count <= 40,
              parts.enumerated().allSatisfy({ isNameWord($0.element, isFirst: $0.offset == 0) }) else { return 0 }
        let words = PaperText.words(text)
        var score = parts.count <= 3 ? 3 : 2
        if words.contains(where: { word in PaperKeywords.surnameSuffixes.contains { word.count > $0.count + 1 && word.hasSuffix($0) } }) {
            score += 2
        }
        if words.contains(where: PaperKeywords.givenNames.contains) { score += 2 }
        if words.contains(where: PaperKeywords.nameParticles.contains) { score += 1 }
        if maxHeight > 0, candidate.height >= maxHeight * 0.95 { score += 1 }
        if rank < 2 { score += 1 }
        if titleScore(text) > 0 { score -= 6 }
        let company = companyScore(text, labels: labels)
        if company >= 2 { score -= 6 } else if company == 1 { score -= 2 }
        return score
    }

    // MARK: Helpers

    /// Index of the highest-scoring candidate (at least `minimum`); ties go to the one read first.
    private static func bestCandidate(in pool: [RoleCandidate], minimum: Int, score: (Int) -> Int) -> Int? {
        var winner: (index: Int, score: Int)?
        for index in pool.indices {
            let value = score(index)
            guard value >= minimum else { continue }
            if let current = winner, current.score > value || (current.score == value && pool[current.index].index < pool[index].index) {
                continue
            }
            winner = (index, value)
        }
        return winner?.index
    }

    /// A capitalised word (letters, apostrophes, hyphens, an initial's dot) or a lower-case particle.
    private static func isNameWord(_ word: String, isFirst: Bool) -> Bool {
        let allowed = word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "." || PaperText.apostrophes.contains($0) }
        guard allowed, let first = word.first, first.isLetter else { return false }
        if first.isUppercase { return true }
        return !isFirst && PaperKeywords.nameParticles.contains(word.lowercased())
    }

    /// "CTO at Payme", "Product Designer, Tezkor", "Директор — Uzum" → (title, company).
    static func splitTitleAndCompany(_ text: String) -> (title: String, company: String?) {
        for separator in [" at ", " @ ", ", ", " — ", " – ", " - ", " / "] {
            guard let range = text.range(of: separator, options: .caseInsensitive) else { continue }
            let left = PaperText.cleanLeftover(String(text[..<range.lowerBound]))
            let right = PaperText.cleanLeftover(String(text[range.upperBound...]))
            guard !left.isEmpty, !right.isEmpty else { continue }
            let leftIsTitle = titleScore(left) > 0
            let rightIsTitle = titleScore(right) > 0
            if leftIsTitle, !rightIsTitle { return (left, right) }
            if rightIsTitle, !leftIsTitle, separator != " at " { return (right, left) }
        }
        return (text, nil)
    }

    private static func looksLikeTitle(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1...6).contains(words.count), !PaperText.hasDigits(text) else { return false }
        // A single all-caps word is a logo / company, not a role.
        return words.count > 1 || !PaperText.isAllCaps(text)
    }

    private static func looksLikeCompany(_ text: String) -> Bool {
        let words = text.split(separator: " ")
        guard (1...4).contains(words.count) else { return false }
        // Taglines ("we build the future") are mostly lower-case.
        let lowercaseWords = words.count { $0.first?.isLowercase == true }
        return lowercaseWords < 2
    }

    /// Second-level labels of company domains ("tezkor" for "tezkor.uz"), free mail providers excluded.
    static func companyLabels(from domains: [String]) -> Set<String> {
        Set(domains.compactMap { domain in
            let parts = domain.lowercased().split(separator: ".").filter { $0 != "www" }
            guard parts.count >= 2 else { return nil }
            let label = String(parts[parts.count - 2])
            return PaperKeywords.freeMailDomains.contains(label) ? nil : label
        })
    }
}
