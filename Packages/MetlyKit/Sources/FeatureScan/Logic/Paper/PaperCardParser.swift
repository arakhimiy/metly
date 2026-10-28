import Foundation
import MetlyCardKit
import MetlyCore

/// What a paper-card scan produced: the editable draft plus what PAPER_REVIEW shows next to it.
nonisolated struct PaperScan: Equatable, Sendable {
    var draft: PaperCardDraft
    /// The card's text pieces in reading order ("Recognized Text" on PAPER_REVIEW).
    var recognizedText: [String] = []
    /// Name / title / company values with strong evidence — shown without the "?" hint.
    var confidentFields: Set<PaperField> = []
}

/// The heuristic reading of a card, kept whole so the on-device model's answer can be merged in.
nonisolated struct PaperAnalysis: Sendable {
    /// Lines in reading order (low-confidence ones dropped).
    var lines: [OCRLine]
    var segments: [String]
    var candidates: [RoleCandidate]
    var context: RoleContext
    var contacts: PaperContacts
    var roles: PaperRoles

    var scan: PaperScan {
        PaperScan(draft: PaperCardParser.draft(roles: roles, contacts: contacts), recognizedText: segments,
                  confidentFields: roles.confident)
    }
}

/// Turns OCR lines of a paper business card into an editable `PaperCardDraft`.
///
/// 1. Lines are put in reading order (two-column cards: left column first — `PaperLayout`).
/// 2. Each line is split on separators ("|", "•", "·") and contact values are pulled out
///    (`PaperContactExtractor`: emails, websites, t.me / LinkedIn links, @handles, every phone with its label).
/// 3. What is left — and isn't an address, a slogan or a stray label — competes for name, job title
///    and company (`PaperRoleClassifier`).
nonisolated enum PaperCardParser {
    /// Lines below this recognition confidence are ignored.
    static let minimumConfidence = 0.3

    static func analyze(_ lines: [OCRLine]) -> PaperAnalysis {
        let ordered = PaperLayout.readingOrder(lines.filter { $0.confidence >= minimumConfidence })
        let extractor = PaperContactExtractor()
        var contacts = PaperContacts()
        var candidates: [RoleCandidate] = []
        var pieces: [String] = []

        for (index, line) in ordered.enumerated() {
            for segment in Self.segments(of: line.text) {
                pieces.append(segment)
                let leftover = PaperText.cleanLeftover(extractor.extract(from: segment, into: &contacts))
                if isRoleCandidate(leftover) {
                    candidates += PaperRoleClassifier.split(RoleCandidate(text: leftover, index: index, height: line.height))
                }
            }
        }

        let entities = PaperEntityTagger.entities(for: candidates.map(\.text))
        let context = RoleContext(domains: contacts.domains, entities: entities, candidates: candidates)
        let roles = PaperRoleClassifier.classify(candidates, context: context)
        return PaperAnalysis(lines: ordered, segments: pieces, candidates: candidates, context: context,
                             contacts: contacts, roles: roles)
    }

    static func analyze(text lines: [String]) -> PaperAnalysis {
        analyze(lines.map { OCRLine($0) })
    }

    static func parse(_ lines: [OCRLine]) -> PaperCardDraft {
        analyze(lines).scan.draft
    }

    /// Convenience for plain strings (tests, VisionKit live text without geometry).
    static func parse(text lines: [String]) -> PaperCardDraft {
        parse(lines.map { OCRLine($0) })
    }

    /// "+998 90 000 11 22 | madina@click.uz" → two pieces; whitespace collapsed, empty pieces dropped.
    static func segments(of text: String) -> [String] {
        PaperText.collapseWhitespace(text)
            .split(whereSeparator: { "|•·‧∙".contains($0) })
            .map { PaperText.collapseWhitespace(String($0)) }
            .filter { $0.count(where: { $0.isLetter || $0.isNumber }) >= 2 }
    }

    // MARK: Draft

    /// The first mobile becomes the primary phone (`fields` + `phoneLabel`); the rest are `additionalPhones`.
    static func draft(roles: PaperRoles, contacts: PaperContacts) -> PaperCardDraft {
        var fields: [ContactField] = []
        let phones = contacts.orderedPhones
        if let phone = phones.first { fields.append(ContactField(kind: .phone, value: phone.value)) }
        if let email = contacts.emails.first { fields.append(ContactField(kind: .email, value: email)) }
        if let telegram = contacts.telegrams.first {
            fields.append(ContactField(kind: .telegram, value: ContactValueFormat.telegramDisplay(username: telegram)))
        }
        if let website = contacts.websites.first { fields.append(ContactField(kind: .website, value: website)) }
        if let linkedin = contacts.linkedins.first { fields.append(ContactField(kind: .linkedin, value: linkedin)) }
        return PaperCardDraft(fullName: roles.name, jobTitle: roles.title, company: roles.company, fields: fields,
                              phoneLabel: phones.first?.label ?? .mobile,
                              additionalPhones: phones.dropFirst().map { LabeledPhone(label: $0.label, value: $0.value) })
    }

    // MARK: Candidates

    /// Text worth classifying: some letters, not only label words, not an address or a city.
    static func isRoleCandidate(_ text: String) -> Bool {
        guard PaperText.letterCount(text) >= 2, !PaperLabel.isLabelWord(text) else { return false }
        let words = PaperText.words(text)
        guard !words.allSatisfy({ PaperLabel.isLabelWord($0) }) else { return false }
        return !isAddress(text)
    }

    static func isAddress(_ text: String) -> Bool {
        let words = PaperText.words(text)
        guard !words.isEmpty else { return false }
        if words.allSatisfy({ PaperKeywords.locationWords.contains($0) }) { return true }
        let hasDigits = PaperText.hasDigits(text)
        if hasDigits, words.contains(where: { PaperKeywords.streetWords.contains($0) || PaperKeywords.locationWords.contains($0) }) {
            return true
        }
        // Without a house number only unmistakable street words count ("Office Manager" is a title).
        if words.contains(where: PaperKeywords.streetNames.contains) { return true }
        return hasDigits && PaperText.letterCount(text) < text.count / 2
    }
}

extension PaperCardDraft {
    /// Enough was read to open PAPER_REVIEW (a name or at least one contact value);
    /// otherwise SCAN shows ALERT_PAPER_NOT_READ.
    nonisolated var isReadable: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty || fields.contains { !$0.isEmpty }
            || additionalPhones.contains { !$0.isEmpty }
    }

    /// Number of filled fields ("4 fields found"); every phone counts.
    nonisolated var detectedFieldCount: Int {
        [fullName, jobTitle, company].count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            + fields.count { !$0.isEmpty }
            + additionalPhones.count { !$0.isEmpty }
    }
}
