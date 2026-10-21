import Foundation

/// MECARD contact QR codes (NTT docomo format, also written by many QR generators):
/// `MECARD:N:Yusupova,Kamila;ORG:Uzum;TEL:+998901234567;EMAIL:kamila@uzum.uz;URL:uzum.uz;;`.
/// They're converted to vCard 3.0 text so they open the same contact review as a vCard QR
/// (SPEC §9 Q41) instead of "No Business Card Found".
nonisolated enum MECardConverter {
    static let prefix = "MECARD:"

    static func isMECard(_ text: String) -> Bool {
        text.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil
    }

    /// The equivalent vCard, or nil when `text` isn't a MECARD.
    static func vCard(fromMECard text: String) -> String? {
        guard isMECard(text) else { return nil }
        var lines = ["BEGIN:VCARD", "VERSION:3.0"]
        for field in split(text.dropFirst(prefix.count), on: ";") {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            let raw = String(field[field.index(after: colon)...])
            switch key {
            case "N":
                // "Family,Given" (a comma splits last and first name), or the whole name.
                let parts = split(Substring(raw), on: ",").map { unescape($0).trimmingCharacters(in: .whitespaces) }
                let family = parts.first ?? ""
                let given = parts.dropFirst().joined(separator: " ")
                let fullName = [given, family].filter { !$0.isEmpty }.joined(separator: " ")
                guard !fullName.isEmpty else { continue }
                lines.append("N:\(escape(family));\(escape(given));;;")
                lines.append("FN:\(escape(fullName))")
            case "TEL", "EMAIL", "URL", "ORG", "TITLE":
                let value = unescape(Substring(raw)).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty else { continue }
                lines.append("\(key):\(escape(value))")
            default:
                continue   // SOUND, NOTE, ADR, BDAY, NICKNAME, TEL-AV… aren't stored
            }
        }
        lines.append("END:VCARD")
        return lines.joined(separator: "\r\n")
    }

    // MARK: Helpers

    /// Splits on `separator` that isn't escaped with a backslash; escapes stay in the parts.
    private static func split(_ text: Substring, on separator: Character) -> [Substring] {
        var parts: [Substring] = []
        var start = text.startIndex
        var index = text.startIndex
        var escaping = false
        while index < text.endIndex {
            let character = text[index]
            if escaping {
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else if character == separator {
                parts.append(text[start..<index])
                start = text.index(after: index)
            }
            index = text.index(after: index)
        }
        parts.append(text[start...])
        return parts.filter { !$0.isEmpty }
    }

    /// `\;` `\:` `\,` `\\` → the character itself.
    private static func unescape(_ value: Substring) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                result.append(character)
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        return result
    }

    /// vCard TEXT escaping (backslash, comma, semicolon, newlines).
    private static func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: ",", with: "\\,")
            .replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: "\r\n", with: "\\n")
            .replacingOccurrences(of: "\n", with: "\\n")
    }
}
