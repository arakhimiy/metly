import Foundation

nonisolated struct PaperRoles: Equatable, Sendable {
    var name = ""
    var title = ""
    var company = ""
    /// Roles with strong evidence (they get no "?" hint on PAPER_REVIEW).
    var confident: Set<PaperField> = []

    subscript(field: PaperField) -> String {
        get {
            switch field {
            case .name: name
            case .title: title
            case .company: company
            default: ""
            }
        }
        set {
            switch field {
            case .name: name = newValue
            case .title: title = newValue
            case .company: company = newValue
            default: break
            }
        }
    }

    static let fields: [PaperField] = [.name, .title, .company]
}

/// Decides which lines are the person's name, job title and company.
///
/// Every candidate gets a name, title and company score from its evidence (`RoleEvidence`):
/// name shape plus given-name / surname dictionaries and `NLTagger` for the name; job words for the
/// title; legal forms, company nouns, quotes and — strongest — the email / website domain for the
/// company. Type size and position only nudge: the biggest line at the top is as often the brand
/// as the person. The best *combination* wins (so a brand that looks like a name loses to a real
/// name and becomes the company instead of pushing the name into Company), with a bonus for a
/// title right under the name — the usual "Name / Title" pair.
nonisolated enum PaperRoleClassifier {
    /// - Parameter pinned: roles already decided (the on-device model's validated answer, or the
    ///   user); their lines are taken out and only the other roles are searched.
    static func classify(_ candidates: [RoleCandidate], context: RoleContext, pinned: PaperRoles = PaperRoles()) -> PaperRoles {
        let pinnedName = pinned.name.isEmpty ? nil : candidates.first { overlaps($0.text, pinned.name) }?.index
        let pool = candidates.filter { candidate in
            !PaperRoles.fields.contains { field in !pinned[field].isEmpty && overlaps(candidate.text, pinned[field]) }
        }
        let evidence = pool.map { RoleEvidence($0, context: context) }
        let nameScores = pinned.name.isEmpty ? evidence.map(nameScore) : evidence.map { _ in nil }
        let titleScores = pinned.title.isEmpty ? evidence.map(titleBase) : evidence.map { _ in nil }
        let companyScores = pinned.company.isEmpty ? evidence.map(companyScore) : evidence.map { _ in nil }

        var best: (score: Double, name: Int?, title: Int?, company: Int?, titleScore: Double) = (0, nil, nil, nil, 0)
        for name in [nil] + pool.indices.filter({ nameScores[$0] != nil }) {
            let nameValue = name.flatMap { nameScores[$0] } ?? 0
            let nameIndex = name.map { pool[$0].index } ?? pinnedName
            for title in [nil] + pool.indices.filter({ titleScores[$0] != nil && $0 != name }) {
                var titleValue = 0.0
                if let title {
                    titleValue = (titleScores[title] ?? 0) + adjacency(pool[title], nameIndex: nameIndex)
                    guard titleValue >= 1.5 else { continue }
                }
                for company in [nil] + pool.indices.filter({ companyScores[$0] != nil && $0 != name && $0 != title }) {
                    let total = nameValue + titleValue + (company.flatMap { companyScores[$0] } ?? 0)
                    if total > best.score + 0.001 { best = (total, name, title, company, titleValue) }
                }
            }
        }

        var roles = pinned
        roles.confident = []
        if let name = best.name {
            roles.name = PaperText.titleCasedIfAllCaps(pool[name].text)
            if (nameScores[name] ?? 0) >= 6 { roles.confident.insert(.name) }
        }
        if let title = best.title {
            roles.title = PaperText.titleCasedIfAllCaps(pool[title].text)
            if evidence[title].titleKeywords >= 2 { roles.confident.insert(.title) }
        }
        if let company = best.company {
            roles.company = pool[company].text
            if (companyScores[company] ?? 0) >= 4 { roles.confident.insert(.company) }
        }
        roles.name = PaperText.titleCasedIfAllCaps(roles.name)
        roles.title = PaperText.titleCasedIfAllCaps(roles.title)
        return roles
    }

    // MARK: Scores (nil = can't be this role)

    static func nameScore(_ e: RoleEvidence) -> Double? {
        guard e.isNameShaped, !e.isTagline else { return nil }
        var score = 2.0
        if e.givenNames > 0 { score += 3 }
        if e.givenNames > 1 { score += 1 }
        if e.surnames > 0 { score += 2 }
        if e.hasParticle { score += 1 }
        switch e.entity {
        case .person: score += 2
        case .organization: score -= 2
        case nil: break
        }
        if e.titleKeywords > 0 { score -= 5 }
        if e.hasLegalForm { score -= 6 }
        if e.hasCompanyNoun { score -= 3 }
        if e.hasQuotes { score -= 3 }
        if e.hasAmpersand { score -= 2 }
        switch e.domain {
        case .exact: score -= 4
        case .partial: score -= 2
        case .none: break
        }
        if e.followsAt { score -= 3 }
        if e.isLargest { score += 0.5 }
        return score >= 2 ? score : nil
    }

    /// Job words; a line without any can still be the title when it sits right under the name.
    static func titleBase(_ e: RoleEvidence) -> Double? {
        guard !e.isTagline, (1...7).contains(e.wordCount), !e.hasDigits else { return nil }
        var score = Double(e.titleKeywords) * 1.5
        if e.hasLegalForm { score -= 3 }
        if e.domain == .exact { score -= 3 }
        if e.givenNames > 0, e.titleKeywords == 0 { score -= 2 }
        if e.titleKeywords == 0, e.wordCount == 1, e.isAllCaps { return nil }
        return score
    }

    static func companyScore(_ e: RoleEvidence) -> Double? {
        guard !e.isTagline, e.wordCount <= 6 else { return nil }
        var score = 0.0
        if e.hasLegalForm { score += 4 }
        if e.hasCompanyNoun { score += 2 }
        if e.hasQuotes { score += 2 }
        if e.hasAmpersand { score += 1 }
        if e.followsAt { score += 2 }
        switch e.domain {
        case .exact: score += 5
        case .partial: score += 3
        case .none: break
        }
        switch e.entity {
        case .organization: score += 2
        case .person: score -= 2
        case nil: break
        }
        if e.isNameShaped {
            if e.givenNames > 0 { score -= 3 }
            if e.surnames > 0 { score -= 2 }
        }
        if e.titleKeywords > 0, !e.hasLegalForm { score -= 3 }
        if e.wordCount <= 4, e.lowercaseWords < 2 { score += 1 }
        if e.isLogoLike { score += 1 }
        if e.isFirst, e.isLogoLike || e.isLargest { score += 1 }
        if e.isLargest { score += 0.5 }
        if e.hasDigits, !e.hasLegalForm { score -= 1 }
        return score >= 1 ? score : nil
    }

    /// "Name / Title": a title right under the name (or the other half of "Name, Title").
    private static func adjacency(_ candidate: RoleCandidate, nameIndex: Int?) -> Double {
        guard let nameIndex, candidate.index == nameIndex + 1 || candidate.index == nameIndex else { return 0 }
        return 1.5
    }

    // MARK: Splitting combined lines

    /// "CTO at Payme", "Aziza Karimova, Product Designer", "Директор — Uzum" → two candidates
    /// when exactly one side has job words; otherwise the line stays whole.
    static func split(_ candidate: RoleCandidate) -> [RoleCandidate] {
        let text = candidate.text
        for separator in [" at ", " @ ", ", ", " — ", " – ", " - ", " / "] {
            guard let range = text.range(of: separator, options: .caseInsensitive) else { continue }
            let left = PaperText.cleanLeftover(String(text[..<range.lowerBound]))
            let right = PaperText.cleanLeftover(String(text[range.upperBound...]))
            guard PaperText.letterCount(left) >= 2, PaperText.letterCount(right) >= 2 else { continue }
            let leftIsTitle = RoleEvidence.titleScore(left) > 0
            let rightIsTitle = RoleEvidence.titleScore(right) > 0
            guard leftIsTitle != rightIsTitle else { continue }
            let isAt = separator == " at " || separator == " @ "
            if isAt, !leftIsTitle { continue }
            var first = candidate
            first.text = left
            var second = candidate
            second.text = right
            second.followsAt = isAt
            return [first, second]
        }
        return [candidate]
    }

    /// Same text, or one contains the other ("Aziza Karimova" inside "Aziza Karimova, Designer").
    static func overlaps(_ lhs: String, _ rhs: String) -> Bool {
        let a = PaperText.comparable(lhs).split(separator: " "), b = PaperText.comparable(rhs).split(separator: " ")
        guard !a.isEmpty, !b.isEmpty else { return false }
        return containsRun(a, b) || containsRun(b, a)
    }

    /// Whether `words` contains `run` as consecutive whole words.
    private static func containsRun(_ words: [Substring], _ run: [Substring]) -> Bool {
        guard run.count <= words.count else { return false }
        return (0...(words.count - run.count)).contains { start in Array(words[start..<(start + run.count)]) == run }
    }
}
