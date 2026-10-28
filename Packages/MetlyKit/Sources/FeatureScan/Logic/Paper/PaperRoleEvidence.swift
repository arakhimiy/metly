import Foundation

/// A text line left after contact values were removed — a name, title or company candidate.
nonisolated struct RoleCandidate: Equatable, Sendable {
    var text: String
    /// Reading order on the card (index of the source line).
    var index: Int
    /// Relative text height (0 = unknown).
    var height: Double
    /// The right-hand side of "CTO at Payme" / "Designer @ Tezkor" — a company hint.
    var followsAt = false
}

/// What the card says about the whole set of candidates (domains, named entities, sizes).
nonisolated struct RoleContext: Sendable {
    /// Second-level labels of company domains ("tezkor" for "tezkor.uz"), free mail providers excluded.
    var domainLabels: Set<String> = []
    /// NLTagger name type per candidate text.
    var entities: [String: PaperEntity] = [:]
    var maxHeight: Double = 0
    var firstIndex = 0

    init(domains: [String] = [], entities: [String: PaperEntity] = [:], candidates: [RoleCandidate] = []) {
        domainLabels = Self.companyLabels(from: domains)
        self.entities = entities
        maxHeight = candidates.map(\.height).max() ?? 0
        firstIndex = candidates.map(\.index).min() ?? 0
    }

    static func companyLabels(from domains: [String]) -> Set<String> {
        Set(domains.compactMap { domain in
            let parts = domain.lowercased().split(separator: ".").filter { $0 != "www" }
            guard parts.count >= 2 else { return nil }
            let label = String(parts[parts.count - 2])
            return PaperKeywords.freeMailDomains.contains(label) ? nil : label
        })
    }
}

/// Everything the heuristics know about one candidate line.
nonisolated struct RoleEvidence: Equatable, Sendable {
    enum DomainMatch: Equatable, Sendable { case none, partial, exact }

    var wordCount = 0
    /// 2–4 capitalised words (or lower-case particles), no digits.
    var isNameShaped = false
    var givenNames = 0
    var surnames = 0
    var hasParticle = false
    var titleKeywords = 0
    var hasLegalForm = false
    var hasCompanyNoun = false
    var hasQuotes = false
    var hasAmpersand = false
    var domain = DomainMatch.none
    var entity: PaperEntity?
    var isTagline = false
    /// One word, or a short all-caps line: how logos read.
    var isLogoLike = false
    var lowercaseWords = 0
    var hasDigits = false
    var isAllCaps = false
    var isLargest = false
    var isFirst = false
    var followsAt = false

    init(_ candidate: RoleCandidate, context: RoleContext) {
        let text = candidate.text
        let parts = text.split(separator: " ").map(String.init)
        let words = PaperText.words(text)
        wordCount = parts.count
        hasDigits = PaperText.hasDigits(text)
        isAllCaps = PaperText.isAllCaps(text)
        isNameShaped = (2...4).contains(parts.count) && !hasDigits && text.count <= 40
            && parts.enumerated().allSatisfy { Self.isNameWord($0.element, isFirst: $0.offset == 0) }
        givenNames = words.count(where: PaperNames.isGivenName)
        surnames = words.count(where: PaperNames.isSurname)
        hasParticle = words.contains(where: PaperKeywords.nameParticles.contains)
        titleKeywords = Self.titleScore(text)
        hasLegalForm = words.contains(where: PaperKeywords.legalForms.contains)
        hasCompanyNoun = words.contains { word in PaperKeywords.companyStems.contains { Self.matches(word, stem: $0) } }
        hasQuotes = text.contains(where: { "«»\"“”„".contains($0) })
        hasAmpersand = text.contains("&")
        domain = Self.domainMatch(text, labels: context.domainLabels)
        entity = context.entities[text]
        lowercaseWords = parts.count { word in
            guard let first = word.first(where: \.isLetter) else { return false }
            return first.isLowercase && !Self.smallWords.contains(word.lowercased())
        }
        isLogoLike = parts.count == 1 || (PaperText.isAllCaps(text) && parts.count <= 3)
        isTagline = Self.isTagline(text, words: words, lowercaseWords: lowercaseWords, titleKeywords: titleKeywords,
                                   hasLegalForm: hasLegalForm, hasCompanyNoun: hasCompanyNoun)
        isLargest = context.maxHeight > 0 && candidate.height >= context.maxHeight * 0.95
        isFirst = candidate.index == context.firstIndex
        followsAt = candidate.followsAt
    }

    /// Any sign of a company: legal form, company noun, quotes, "&", the email/website domain.
    var hasCompanySignal: Bool {
        hasLegalForm || hasCompanyNoun || hasQuotes || hasAmpersand || domain != .none || entity == .organization
    }

    /// Strong signs of a person: a known given name together with a surname (dictionary or ending).
    var looksLikePerson: Bool { isNameShaped && givenNames > 0 && surnames > 0 }

    // MARK: Helpers

    /// Job-title strength: strong words count double; modifiers only count in pairs.
    static func titleScore(_ text: String) -> Int {
        let words = PaperText.wordsAndParts(text)
        let strong = words.count { word in PaperKeywords.strongTitleStems.contains { matches(word, stem: $0) } }
        let weak = words.count { word in PaperKeywords.weakTitleStems.contains { matches(word, stem: $0) } }
        if strong > 0 { return strong * 2 + weak }
        return weak >= 2 ? weak : 0
    }

    /// Prefix match, except short stems ("lab", "it", "банк") which must be the whole word.
    static func matches(_ word: String, stem: String) -> Bool {
        stem.count <= 4 ? word == stem : word.hasPrefix(PaperText.unifyingApostrophes(stem))
    }

    static func domainMatch(_ text: String, labels: Set<String>) -> DomainMatch {
        let letters = PaperText.letters(text)
        guard letters.count >= 3 else { return .none }
        let candidates = labels.filter { $0.count >= 3 }
        if candidates.contains(where: { $0.filter(\.isLetter) == letters }) { return .exact }
        if candidates.contains(where: { letters.contains($0) || $0.contains(letters) }) { return .partial }
        return .none
    }

    /// A capitalised word (letters, apostrophes, hyphens, an initial's dot) or a lower-case particle.
    static func isNameWord(_ word: String, isFirst: Bool) -> Bool {
        let allowed = word.allSatisfy { $0.isLetter || $0 == "-" || $0 == "." || PaperText.apostrophes.contains($0) }
        guard allowed, let first = word.first, first.isLetter else { return false }
        if first.isUppercase { return true }
        return !isFirst && PaperKeywords.nameParticles.contains(PaperText.unifyingApostrophes(word.lowercased()))
    }

    /// Slogans: start like a sentence ("Your…", "Мы…"), end with "!" / ".", or are mostly lower-case
    /// words without a job title, legal form or company noun ("Home appliances for every family" —
    /// but not "Toshkent davlat iqtisodiyot universiteti").
    static func isTagline(_ text: String, words: [String], lowercaseWords: Int, titleKeywords: Int,
                          hasLegalForm: Bool, hasCompanyNoun: Bool) -> Bool {
        guard words.count >= 3, !hasLegalForm else { return false }
        if let first = words.first, PaperKeywords.taglineLeads.contains(where: { matches(first, stem: $0) }) { return true }
        if let last = text.trimmingCharacters(in: .whitespaces).last, "!.".contains(last) { return true }
        return lowercaseWords >= 2 && titleKeywords == 0 && !hasCompanyNoun
    }

    private static let smallWords: Set<String> = [
        "of", "and", "at", "for", "the", "in", "&", "и", "по", "va", "de", "da", "van", "von", "o'g'li", "qizi",
    ]
}
