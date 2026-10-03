import Foundation
import MetlyCardKit

/// Contact values found on a card, in the order they were read.
nonisolated struct PaperContacts: Equatable, Sendable {
    struct Phone: Equatable, Sendable {
        var value: String
        var isMobile: Bool
    }

    var phones: [Phone] = []
    var emails: [String] = []
    /// Bare usernames (no "@").
    var telegrams: [String] = []
    /// Display form ("tezkor.uz").
    var websites: [String] = []
    /// Display form ("in/azizakarimova").
    var linkedins: [String] = []

    /// Mobile first (it's the one people answer), else the first number read.
    var preferredPhone: String? {
        (phones.first(where: \.isMobile) ?? phones.first)?.value
    }

    /// Hosts of the email addresses and websites ("tezkor.uz") — used to recognise the company line.
    var domains: [String] {
        emails.compactMap { $0.split(separator: "@").last.map(String.init) }
            + websites.compactMap { ContactValueFormat.websiteURL(from: $0)?.host()?.lowercased() }
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

    private func extractPhones(from text: String, label: PaperLabel?, into contacts: inout PaperContacts) -> String {
        var result = text
        var found: [(Range<String.Index>, String)] = []
        if let detector {
            for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            where match.resultType == .phoneNumber {
                if let range = Range(match.range, in: text) { found.append((range, String(text[range]))) }
            }
        }
        for match in text.matches(of: Self.phone) where !found.contains(where: { $0.0.overlaps(match.range) }) {
            found.append((match.range, String(match.output)))
        }
        let valid = found
            .filter { PhoneFormat.isPlausible($0.1) }
            .sorted { $0.0.lowerBound < $1.0.lowerBound }
        if label != .fax {
            for (_, value) in valid {
                let isMobile = label == .phone(mobile: true) || PhoneFormat.isUzbekMobile(value)
                contacts.phones.append(PaperContacts.Phone(value: PhoneFormat.display(value), isMobile: isMobile))
            }
        }
        for (range, _) in valid.reversed() {
            result.replaceSubrange(range, with: " ")
        }
        return result
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
        /\b[A-Za-z0-9][A-Za-z0-9\-]*(?:\.[A-Za-z0-9\-]+)*\.(?:com|net|org|uz|ru|io|co|me|ai|app|dev|info|biz|kz|kg|tj|tm|az|ge|am|by|ua|de|uk|us|eu|tech|design|studio|agency|pro|online|site|store|shop|xyz|edu|gov|academy|group|link|page|cloud|digital|global|team|works|space|world|live|fm|tv|gg|so|to)\b(?:\/[^\s,;]*)?/
            .ignoresCase()
    }
    private static var handle: Regex<Substring> { /@[A-Za-z0-9_.]{3,32}/ }
    private static var phone: Regex<Substring> { /\+?\(?\d[\d\s().\-]{5,}\d/ }
}
