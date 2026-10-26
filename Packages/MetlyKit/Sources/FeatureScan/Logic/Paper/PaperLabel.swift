import Foundation

/// A field label printed before a value ("Tel.:", "E-mail:", "Моб.", "Telegram:").
nonisolated enum PaperLabel: Equatable, Sendable {
    case phone(mobile: Bool)
    case fax
    case email
    case website
    case telegram
    case linkedin
    /// Networks Tanishly doesn't store (Instagram, Facebook…): the value is ignored.
    case ignored

    /// Splits a leading label off `segment`. Labels end with ":" ("Tel: …"), or are short
    /// prefixes directly followed by the value ("M +998…", "E aziza@…").
    static func split(_ segment: String) -> (label: PaperLabel?, value: String) {
        let text = segment.trimmingCharacters(in: .whitespaces)
        if let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }), text.distance(from: text.startIndex, to: colon) <= 16 {
            let word = text[..<colon]
            if let label = label(for: word) {
                return (label, String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespaces))
            }
        }
        if let space = text.firstIndex(of: " ") {
            let word = text[..<space]
            let rest = text[text.index(after: space)...].trimmingCharacters(in: .whitespaces)
            if word.count <= 8, let first = rest.first, first == "+" || first == "(" || first == "@" || first.isNumber,
               let label = label(for: word) {
                return (label, rest)
            }
        }
        return (nil, text)
    }

    /// A bare label word left over on its own line ("Mobile", "Факс") — never a name or company.
    static func isLabelWord(_ text: String) -> Bool {
        label(for: Substring(text)) != nil
    }

    private static func label(for word: Substring) -> PaperLabel? {
        let key = word.lowercased()
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: .whitespaces)
        return table[key]
    }

    private static let table: [String: PaperLabel] = {
        var table: [String: PaperLabel] = [:]
        for key in ["tel", "phone", "ph", "t", "office", "work", "тел", "телефон", "telefon", "raqam", "р", "т"] {
            table[key] = .phone(mobile: false)
        }
        for key in ["mob", "mobile", "m", "cell", "моб", "мобильный", "mobil", "uyali", "whatsapp", "wa", "viber", "м"] {
            table[key] = .phone(mobile: true)
        }
        for key in ["fax", "f", "факс", "faks", "ф"] { table[key] = .fax }
        for key in ["email", "e-mail", "e", "mail", "почта", "эл почта", "e-pochta", "pochta", "email address"] {
            table[key] = .email
        }
        for key in ["web", "w", "site", "website", "сайт", "veb-sayt", "sayt", "url", "www"] { table[key] = .website }
        for key in ["telegram", "tg", "телеграм", "телеграмм", "telegramm"] { table[key] = .telegram }
        for key in ["linkedin", "in", "li"] { table[key] = .linkedin }
        for key in ["instagram", "insta", "inst", "ig", "facebook", "fb", "twitter", "x", "tiktok", "youtube"] {
            table[key] = .ignored
        }
        return table
    }()
}
