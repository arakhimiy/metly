import Foundation
import MetlyCardKit
import MetlyCore

/// Checks the model's answer against what the camera actually read. A value survives only when
/// it is (fuzzily) present in the OCR text — and it is then replaced by the OCR text itself, so a
/// model that "fixed" a spelling or changed the case can't slip anything in. Values that fail are
/// dropped and the heuristics fill that field instead.
nonisolated enum PaperModelValidator {
    /// Minimum similarity between the model's value and a run of words on the card.
    static let minimumSimilarity = 0.85

    static func validate(_ output: PaperModelOutput, against analysis: PaperAnalysis) -> PaperModelOutput {
        let segments = analysis.segments
        let context = analysis.context
        var result = PaperModelOutput()

        // Name, title, company: a run of words from one of the role lines — the text left once
        // contacts, labels and addresses are taken out — so a website ("karimov.uz") or an email
        // can't become the company. Then sanity-checked against the evidence.
        var seen = Set<String>()
        let roleLines = analysis.candidates.map(\.text).filter { seen.insert($0).inserted }
        if let name = span(matching: output.fullName, in: roleLines), isPlausibleName(name, context: context) {
            result.fullName = PaperText.titleCasedIfAllCaps(name)
        }
        if let title = span(matching: output.jobTitle, in: roleLines), isPlausibleRole(title),
           !PaperRoleClassifier.overlaps(title, result.fullName) {
            result.jobTitle = PaperText.titleCasedIfAllCaps(title)
        }
        if let company = span(matching: output.company, in: roleLines), isPlausibleCompany(company, context: context),
           !PaperRoleClassifier.overlaps(company, result.fullName), !PaperRoleClassifier.overlaps(company, result.jobTitle) {
            result.company = company
        }

        // Contacts: must appear in the text (digits for phones, case-insensitive for the rest).
        let text = segments.joined(separator: "\n")
        let lowered = text.lowercased()
        let digitRuns = segments.map(PhoneFormat.digits)
        for phone in output.phones {
            guard let number = validatedPhone(phone.number, digitRuns: digitRuns, known: analysis.contacts.phones),
                  !result.phones.contains(where: { PhoneFormat.key($0.number) == PhoneFormat.key(number) }) else { continue }
            result.phones.append(PaperModelOutput.Phone(number: number, label: phone.label))
        }
        let email = output.email.trimmingCharacters(in: .whitespaces).lowercased()
        if email.contains("@"), !email.contains(" "), lowered.contains(email) { result.email = email }
        // A handle must be printed as one ("@user", "t.me/user", or after a Telegram label) — not just a word.
        if let username = ContactValueFormat.telegramUsername(from: output.telegram)?.lowercased(), username.count >= 3,
           lowered.contains("@" + username) || lowered.contains("t.me/" + username)
            || analysis.contacts.telegrams.contains(where: { $0.lowercased() == username }) {
            result.telegram = ContactValueFormat.telegramDisplay(username: username)
        }
        // A website must be printed on its own, not only as the domain of an email address.
        let website = ContactValueFormat.websiteDisplay(from: output.website).lowercased()
        if website.contains("."), !website.contains(" "), !website.contains("@"), containsStandalone(website, in: lowered) {
            result.website = website
        }
        if let url = ContactValueFormat.linkedInURL(from: output.linkedin), output.linkedin.count >= 3 {
            let display = ContactValueFormat.linkedInDisplay(from: url)
            let slug = display.split(separator: "/").last.map { $0.lowercased() } ?? ""
            if slug.count >= 3, lowered.contains(slug) { result.linkedin = display }
        }
        return result
    }

    // MARK: Text spans

    /// The run of words on one line that best matches `value` (≥ 85 % similar after normalising
    /// case, apostrophes and Cyrillic), returned exactly as printed. nil when nothing matches.
    static func span(matching value: String, in segments: [String]) -> String? {
        let target = PaperText.comparable(value)
        let targetWords = target.split(separator: " ").count
        guard targetWords > 0, target.count >= 2 else { return nil }
        var best: (similarity: Double, text: String)?
        for segment in segments {
            let raw = segment.split(separator: " ").map(String.init)
            let normal = raw.map(PaperText.comparable)
            for start in raw.indices {
                for length in max(1, targetWords - 1)...(targetWords + 1) where start + length <= raw.count {
                    let window = normal[start..<(start + length)].filter { !$0.isEmpty }.joined(separator: " ")
                    guard !window.isEmpty else { continue }
                    let similarity = window == target ? 1 : (target.count <= 4 ? 0 : PaperText.similarity(window, target))
                    if similarity > (best?.similarity ?? 0) {
                        best = (similarity, raw[start..<(start + length)].joined(separator: " "))
                    }
                }
            }
        }
        guard let best, best.similarity >= minimumSimilarity else { return nil }
        let cleaned = PaperText.cleanLeftover(best.text)
        return cleaned.isEmpty ? nil : cleaned
    }

    /// `value` occurs in `text` not glued to a preceding word, "." or "@" ("tezkor.uz" in "www.tezkor.uz"
    /// counts — "www." is fine — but not in "aziza@tezkor.uz").
    static func containsStandalone(_ value: String, in text: String) -> Bool {
        var searchStart = text.startIndex
        while let range = text.range(of: value, range: searchStart..<text.endIndex) {
            let before = text[text.startIndex..<range.lowerBound]
            if before.isEmpty || before.hasSuffix("www.") || before.hasSuffix("//")
                || !(before.last.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "@" } ?? false) {
                return true
            }
            searchStart = range.upperBound
        }
        return false
    }

    // MARK: Sanity checks

    /// A person's name: name-shaped words, not a legal entity, not the email/website domain itself.
    static func isPlausibleName(_ text: String, context: RoleContext) -> Bool {
        let evidence = RoleEvidence(RoleCandidate(text: text, index: -1, height: 0), context: context)
        guard (1...5).contains(evidence.wordCount), !evidence.hasDigits, !text.contains("@") else { return false }
        if evidence.hasLegalForm || evidence.domain == .exact || evidence.isTagline { return false }
        if evidence.titleKeywords > 0, evidence.givenNames == 0 { return false }
        return true
    }

    static func isPlausibleRole(_ text: String) -> Bool {
        !text.contains("@") && PaperText.letterCount(text) >= 2 && !PaperText.hasDigits(text)
    }

    /// Not a person's name in disguise (a known given name plus a surname and no company sign).
    static func isPlausibleCompany(_ text: String, context: RoleContext) -> Bool {
        guard !text.contains("@"), PaperText.letterCount(text) >= 2 else { return false }
        let evidence = RoleEvidence(RoleCandidate(text: text, index: -1, height: 0), context: context)
        return !(evidence.looksLikePerson && !evidence.hasCompanySignal)
    }

    /// The model's number when its digits are on the card; the heuristics' formatting when they read it too.
    static func validatedPhone(_ raw: String, digitRuns: [String], known: [PaperContacts.Phone]) -> String? {
        guard !raw.contains("@") else { return nil }
        // "+998 (71) 120-45-00 доб. 210" → the number without its label or extension.
        let number = PhoneContactCleaner.clean(raw)
        guard PhoneFormat.isPlausible(number) else { return nil }
        let key = PhoneFormat.key(number)
        if let match = known.first(where: { PhoneFormat.key($0.value) == key }) { return match.value }
        let digits = PhoneFormat.digits(number)
        guard digitRuns.contains(where: { $0.contains(digits) || $0.contains(key) }) else { return nil }
        return PhoneFormat.display(number)
    }
}

/// Strips a label the model may have copied along with the number ("Mob: +998…").
nonisolated enum PhoneContactCleaner {
    static func clean(_ number: String) -> String {
        guard let start = number.firstIndex(where: { $0.isNumber || $0 == "+" || $0 == "(" }) else { return number }
        return PaperContactExtractor.removingExtension(from: String(number[start...]))
    }
}
