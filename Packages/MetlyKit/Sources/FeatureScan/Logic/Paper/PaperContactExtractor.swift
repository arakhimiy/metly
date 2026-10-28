import Foundation
import MetlyCardKit
import MetlyCore

/// Contact values found on a card, in the order they were read.
nonisolated struct PaperContacts: Equatable, Sendable {
    struct Phone: Equatable, Sendable {
        var value: String
        var label: PhoneLabel
        /// The card printed the kind ("Mob:", "(ish)", "Office") rather than it being guessed from the prefix.
        var isLabelled: Bool
    }

    var phones: [Phone] = []
    var emails: [String] = []
    /// Bare usernames (no "@").
    var telegrams: [String] = []
    /// Display form ("tezkor.uz").
    var websites: [String] = []
    /// Display form ("in/azizakarimova").
    var linkedins: [String] = []
    /// Address lines in reading order ("Amir Temur ko‘chasi 108", "Toshkent").
    var addresses: [String] = []

    /// The address lines joined, when they name a place with a house number or a street; nil otherwise
    /// (a lone "Uzbekistan" isn't an address worth saving).
    var address: String? {
        let joined = addresses.joined(separator: ", ")
        let words = PaperText.words(joined)
        let hasStreet = words.contains { PaperKeywords.streetWords.contains($0) || PaperKeywords.streetNames.contains($0) }
        guard !joined.isEmpty, PaperText.hasDigits(joined) || hasStreet else { return nil }
        return String(joined.prefix(ContactEntry.maxLength(for: .address)))
    }

    /// Every number once, the primary first: the first mobile (it's the one people answer),
    /// else the first number read; the others keep the card's order.
    var orderedPhones: [Phone] {
        guard let primary = phones.firstIndex(where: { $0.label == .mobile }) ?? phones.indices.first else { return [] }
        var ordered = phones
        let first = ordered.remove(at: primary)
        return [first] + ordered
    }

    var preferredPhone: String? { orderedPhones.first?.value }

    /// Adds a number unless it is already there (same last 9 digits); a printed label wins over a guess.
    mutating func add(_ phone: Phone) {
        let key = PhoneFormat.key(phone.value)
        if let index = phones.firstIndex(where: { PhoneFormat.key($0.value) == key }) {
            if phone.isLabelled, !phones[index].isLabelled {
                phones[index].label = phone.label
                phones[index].isLabelled = true
            }
            return
        }
        phones.append(phone)
    }

    /// Hosts of the email addresses and websites ("tezkor.uz") — used to recognise the company line.
    var domains: [String] {
        emails.compactMap { $0.split(separator: "@").last.map(String.init) }
            + websites.compactMap { ContactValueFormat.websiteURL(from: $0)?.host()?.lowercased() }
    }

    var isEmpty: Bool {
        phones.isEmpty && emails.isEmpty && telegrams.isEmpty && websites.isEmpty && linkedins.isEmpty
    }
}

/// Pulls emails, links, Telegram handles and phone numbers out of one text segment
/// (`NSDataDetector` for phones and links, plus patterns for what it misses) and returns the leftover text.
nonisolated struct PaperContactExtractor {
    private let detector = try? NSDataDetector(
        types: NSTextCheckingResult.CheckingType.phoneNumber.rawValue | NSTextCheckingResult.CheckingType.link.rawValue)

    func extract(from segment: String, into contacts: inout PaperContacts) -> String {
        let (label, value) = PaperLabel.split(segment)
        if label == .ignored { return "" }
        var text = value

        // 1. Emails (before links, so "tezkor.uz" inside an address isn't read as a website).
        for match in text.matches(of: Self.email) {
            contacts.emails.append(String(match.output).lowercased())
        }
        text = text.replacing(Self.email, with: " ")

        // 2. Links: Telegram, LinkedIn, then any website.
        for pattern in [Self.telegramLink, Self.linkedInLink, Self.schemeLink, Self.wwwLink, Self.domainLink] {
            for match in text.matches(of: pattern) { add(link: String(match.output), to: &contacts) }
            text = text.replacing(pattern, with: " ")
        }
        text = removeDetectedLinks(from: text, into: &contacts)

        // 3. Telegram handles ("@aziza.k") and bare values after a Telegram / LinkedIn label.
        for match in text.matches(of: Self.handle) {
            let handle = String(match.output.dropFirst()).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if let username = ContactValueFormat.telegramUsername(from: handle) { contacts.telegrams.append(username) }
        }
        text = text.replacing(Self.handle, with: " ")
        text = consumeLabelledValue(text, label: label, into: &contacts)

        // 4. Phone numbers.
        text = extractPhones(from: text, label: label, into: &contacts)
        return text
    }

    // MARK: Links

    private func add(link: String, to contacts: inout PaperContacts) {
        let trimmed = link.trimmingCharacters(in: CharacterSet(charactersIn: ".,;)"))
        guard let url = ContactValueFormat.websiteURL(from: trimmed), let host = url.host()?.lowercased() else { return }
        if ["t.me", "www.t.me", "telegram.me", "telegram.dog"].contains(host) {
            if let username = ContactValueFormat.telegramUsername(from: trimmed) { contacts.telegrams.append(username) }
        } else if host == "linkedin.com" || host.hasSuffix(".linkedin.com") {
            contacts.linkedins.append(ContactValueFormat.linkedInDisplay(from: url))
        } else {
            contacts.websites.append(ContactValueFormat.websiteDisplay(from: trimmed).lowercased())
        }
    }

    /// Links `NSDataDetector` finds that the patterns missed (e.g. unusual TLDs written with a scheme).
    private func removeDetectedLinks(from text: String, into contacts: inout PaperContacts) -> String {
        guard let detector else { return text }
        var result = text
        let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches.reversed() where match.resultType == .link {
            guard let range = Range(match.range, in: text), let url = match.url else { continue }
            let found = String(text[range])
            if url.scheme == "mailto" {
                contacts.emails.append(found.replacingOccurrences(of: "mailto:", with: "").lowercased())
            } else if ["http", "https"].contains(url.scheme ?? ""), found.contains(".") {
                add(link: found, to: &contacts)
            } else {
                continue
            }
            result.replaceSubrange(range, with: " ")
        }
        return result
    }

    private func consumeLabelledValue(_ text: String, label: PaperLabel?, into contacts: inout PaperContacts) -> String {
        let value = text.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, !value.contains(" ") else { return text }
        switch label {
        case .telegram:
            guard let username = ContactValueFormat.telegramUsername(from: value) else { return text }
            contacts.telegrams.append(username)
            return ""
        case .linkedin:
            guard let url = ContactValueFormat.linkedInURL(from: value) else { return text }
            contacts.linkedins.append(ContactValueFormat.linkedInDisplay(from: url))
            return ""
        case .website:
            // "W: silkroad.vc" — any TLD is fine once the card labels it a website.
            guard value.contains("."), ContactValueFormat.websiteURL(from: value)?.host() != nil else { return text }
            add(link: value, to: &contacts)
            return ""
        default:
            return text
        }
    }

    // MARK: Phones

    /// Every plausible number in the segment with its label: the one printed right before it
    /// ("…, Mob: 90 123 45 67"), right after it ("90 123 45 67 (mob.)"), the segment's own label
    /// ("Tel.: …"), else a guess from the prefix. Fax numbers and extensions ("доб. 210") are dropped.
    private func extractPhones(from text: String, label segmentLabel: PaperLabel?, into contacts: inout PaperContacts) -> String {
        var found: [(Range<String.Index>, String)] = []
        if let detector {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            where match.resultType == .phoneNumber {
                if let range = Range(match.range, in: text) { found.append((range, String(text[range]))) }
            }
        }
        // The pattern also catches what the detector cuts short ("(+998 71) 200-11-22" → "200-11-22"):
        // on overlap the plausible match with more digits wins.
        for match in text.matches(of: Self.phone) {
            let value = String(match.output)
            let overlapping = found.indices.filter { found[$0].0.overlaps(match.range) }
            let longest = overlapping.map { PhoneFormat.digits(found[$0].1).count }.max() ?? 0
            guard overlapping.isEmpty || (PhoneFormat.isPlausible(value) && PhoneFormat.digits(value).count > longest) else { continue }
            for index in overlapping.reversed() { found.remove(at: index) }
            found.append((match.range, value))
        }
        let valid = found
            .map { ($0.0, Self.removingExtension(from: $0.1)) }
            .filter { PhoneFormat.isPlausible($0.1) }
            .sorted { $0.0.lowerBound < $1.0.lowerBound }

        var removals: [Range<String.Index>] = []
        for (offset, (range, number)) in valid.enumerated() {
            let previousEnd = offset == 0 ? text.startIndex : valid[offset - 1].0.upperBound
            let nextStart = offset + 1 < valid.count ? valid[offset + 1].0.lowerBound : text.endIndex
            var removal = range
            var after = text[range.upperBound..<max(range.upperBound, nextStart)]
            if let ext = after.prefixMatch(of: Self.extensionSuffix) {
                removal = range.lowerBound..<ext.range.upperBound
                after = text[ext.range.upperBound..<max(ext.range.upperBound, nextStart)]
            }
            removals.append(removal)

            let before = text[min(previousEnd, range.lowerBound)..<range.lowerBound]
            let printed = PaperLabel.trailingLabel(in: before)
                ?? PaperLabel.followingLabel(in: after, allowsBareWord: offset + 1 == valid.count)
                ?? segmentLabel
            guard printed != .fax else { continue }
            let (label, isLabelled) = Self.phoneLabel(printed: printed, number: number)
            contacts.add(PaperContacts.Phone(value: PhoneFormat.display(number), label: label, isLabelled: isLabelled))
        }
        var result = text
        for range in removals.reversed() {
            result.replaceSubrange(range, with: " ")
        }
        return result
    }

    /// A printed kind wins; a generic "Tel" is a work number unless the prefix says mobile; an
    /// unlabelled number follows its prefix and is otherwise taken as the mobile.
    static func phoneLabel(printed: PaperLabel?, number: String) -> (PhoneLabel, isLabelled: Bool) {
        switch printed {
        case .phone(let kind?): (kind, true)
        case .phone(nil): (PhoneFormat.inferredLabel(number) ?? .work, false)
        default: (PhoneFormat.inferredLabel(number) ?? .mobile, false)
        }
    }

    /// "+1 212 555 0100 ext. 12" → "+1 212 555 0100" (an extension can't be dialled from a plain number).
    static func removingExtension(from number: String) -> String {
        guard let match = number.firstMatch(of: extensionSuffix) else { return number }
        return String(number[..<match.range.lowerBound])
    }

    // MARK: Patterns

    private static var email: Regex<Substring> { /[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/ }
    private static var telegramLink: Regex<Substring> {
        /(?:https?:\/\/)?(?:www\.)?(?:t\.me|telegram\.me|telegram\.dog)\/[A-Za-z0-9_.]+/.ignoresCase()
    }
    private static var linkedInLink: Regex<Substring> {
        /(?:https?:\/\/)?(?:[a-z]{2,3}\.)?linkedin\.com\/(?:in|company|pub)\/[A-Za-z0-9_\-%.]+\/?/.ignoresCase()
    }
    private static var schemeLink: Regex<Substring> { /https?:\/\/[^\s,;]+/.ignoresCase() }
    private static var wwwLink: Regex<Substring> { /www\.[^\s,;]+/.ignoresCase() }
    private static var domainLink: Regex<Substring> {
        // Bare domains need a known TLD so "J.Smith" or "Ltd.Co" never become websites.
        /\b[A-Za-z0-9][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)*\.(?:com|net|org|uz|ru|io|co|me|ai|app|dev|info|biz|kz|kg|tj|tm|az|ge|am|by|ua|de|uk|us|eu|tech|design|studio|agency|pro|online|site|store|shop|xyz|edu|gov|academy|group|link|page|cloud|digital|global|team|works|space|world|live|fm|tv|gg|so|to|vc)\b(?:\/[^\s,;]*)?/
            .ignoresCase()
    }
    private static var handle: Regex<Substring> { /@[A-Za-z0-9_.]{3,32}/ }
    private static var phone: Regex<Substring> { /\+?\(?\d[\d\s().\-]{5,}\d/ }
    /// ", доб. 210", " ext. 12", " x12", " вн. 3".
    private static var extensionSuffix: Regex<Substring> {
        /\s*[,;]?\s*(?:доб|ext|вн|x|ichki|qo'sh|добавочный)\.?\s*\d{1,6}/.ignoresCase()
    }
}
