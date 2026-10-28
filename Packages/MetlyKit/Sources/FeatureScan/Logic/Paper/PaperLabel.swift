import Foundation
import MetlyCore

/// A field label printed before (or after) a value ("Tel.:", "E-mail:", "Моб.", "(ish)", "Telegram:").
nonisolated enum PaperLabel: Equatable, Sendable {
    /// A phone number; nil = a generic "Tel" / "Phone" that doesn't say which kind.
    case phone(PhoneLabel?)
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

    /// The label right before a value inside a line: ", Mob: " in "Tel: 71 200 00 00, Mob: 90 123 45 67".
    static func trailingLabel(in text: Substring) -> PaperLabel? {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " :：-–—.,;|"))
        guard !trimmed.isEmpty else { return nil }
        // "Tel/Fax", "моб. тел" — try the last two words, then the last one.
        let words = trimmed.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" })
        if words.count >= 2, let label = label(for: Substring(words.suffix(2).joined(separator: " "))) { return label }
        return words.last.flatMap { label(for: $0) }
    }

    /// A label written after a value: "+998 90 123 45 67 (mob.)", "… моб", "… (ish)".
    static func followingLabel(in text: Substring, allowsBareWord: Bool) -> PaperLabel? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("("), let close = trimmed.firstIndex(of: ")") {
            return label(for: trimmed[trimmed.index(after: trimmed.startIndex)..<close])
        }
        guard allowsBareWord else { return nil }
        let word = trimmed.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }).first
        return word.flatMap { label(for: $0) }
    }

    /// A bare label word left over on its own line ("Mobile", "Факс") — never a name or company.
    static func isLabelWord(_ text: String) -> Bool {
        label(for: Substring(text)) != nil
    }

    static func label(for word: Substring) -> PaperLabel? {
        let key = PaperText.unifyingApostrophes(word.lowercased())
            .replacingOccurrences(of: ".", with: "")
            .trimmingCharacters(in: CharacterSet(charactersIn: " :()"))
        return table[key]
    }

    private static let table: [String: PaperLabel] = {
        var table: [String: PaperLabel] = [:]
        for key in ["tel", "phone", "ph", "t", "тел", "телефон", "telefon", "raqam", "т", "p", "tel raqam"] {
            table[key] = .phone(nil)
        }
        for key in ["mob", "mobile", "m", "cell", "c", "моб", "мобильный", "мобильный телефон", "моб тел", "mobil",
                    "uyali", "сот", "сотовый", "сот тел", "whatsapp", "wa", "viber", "м", "mobile phone", "cell phone",
                    "mob tel", "mobil tel", "mobile tel", "handy"] {
            table[key] = .phone(.mobile)
        }
        for key in ["office", "work", "o", "direct", "business", "раб", "рабочий", "раб тел", "офис", "ish", "ish tel",
                    "ishxona", "idora", "office tel", "work phone", "р", "tel/fax", "tel / fax", "тел/факс", "phone/fax",
                    "office phone", "main", "reception", "приёмная", "приемная", "qabulxona"] {
            table[key] = .phone(.work)
        }
        for key in ["home", "h", "uy", "uy tel", "дом", "домашний", "дом тел", "home phone", "res"] {
            table[key] = .phone(.home)
        }
        for key in ["fax", "f", "факс", "faks", "ф", "telefaks", "телефакс"] { table[key] = .fax }
        for key in ["email", "e-mail", "e", "mail", "почта", "эл почта", "e-pochta", "pochta", "email address", "эл адрес"] {
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
