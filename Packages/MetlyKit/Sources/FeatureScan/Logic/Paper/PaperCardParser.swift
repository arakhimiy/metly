import Foundation
import MetlyCardKit
import MetlyCore

/// Turns OCR lines of a paper business card into an editable `PaperCardDraft`.
///
/// 1. Each line is split on separators ("|", "•", "·") and contact values are pulled out
///    (`PaperContactExtractor`: emails, websites, t.me / LinkedIn links, @handles, phones).
/// 2. What is left — and isn't an address or a stray label — competes for name, job title and
///    company (`PaperRoleClassifier`).
nonisolated enum PaperCardParser {
    /// Lines below this recognition confidence are ignored.
    static let minimumConfidence = 0.3

    static func parse(_ lines: [OCRLine]) -> PaperCardDraft {
        let extractor = PaperContactExtractor()
        var contacts = PaperContacts()
        var candidates: [RoleCandidate] = []

        for (index, line) in lines.enumerated() where line.confidence >= minimumConfidence {
            let text = PaperText.collapseWhitespace(line.text)
            for segment in text.split(whereSeparator: { "|•·‧∙".contains($0) }).map(String.init) {
                let leftover = PaperText.cleanLeftover(extractor.extract(from: segment, into: &contacts))
                if isRoleCandidate(leftover) {
                    candidates.append(RoleCandidate(text: leftover, index: index, height: line.height))
                }
            }
        }

        let roles = PaperRoleClassifier.classify(candidates, domains: contacts.domains)
        return PaperCardDraft(fullName: roles.name, jobTitle: roles.title, company: roles.company,
                              fields: fields(from: contacts))
    }

    /// Convenience for plain strings (tests, VisionKit live text without geometry).
    static func parse(text lines: [String]) -> PaperCardDraft {
        parse(lines.map { OCRLine($0) })
    }

    // MARK: Helpers

    private static func fields(from contacts: PaperContacts) -> [ContactField] {
        var fields: [ContactField] = []
        if let phone = contacts.preferredPhone { fields.append(ContactField(kind: .phone, value: phone)) }
        if let email = contacts.emails.first { fields.append(ContactField(kind: .email, value: email)) }
        if let telegram = contacts.telegrams.first {
            fields.append(ContactField(kind: .telegram, value: ContactValueFormat.telegramDisplay(username: telegram)))
        }
        if let website = contacts.websites.first { fields.append(ContactField(kind: .website, value: website)) }
        if let linkedin = contacts.linkedins.first { fields.append(ContactField(kind: .linkedin, value: linkedin)) }
        return fields
    }

    /// Text worth classifying: some letters, not a lone label, not an address or a city.
    static func isRoleCandidate(_ text: String) -> Bool {
        guard PaperText.letterCount(text) >= 2, !PaperLabel.isLabelWord(text) else { return false }
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
    }

    /// Number of filled fields ("4 fields found").
    nonisolated var detectedFieldCount: Int {
        [fullName, jobTitle, company].count { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            + fields.count { !$0.isEmpty }
    }
}
