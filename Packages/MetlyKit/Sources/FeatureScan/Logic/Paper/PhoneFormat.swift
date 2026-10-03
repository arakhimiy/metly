import Foundation

/// Phone helpers for OCR results (Uzbek numbers get the familiar `+998 90 123 45 67` grouping).
nonisolated enum PhoneFormat {
    /// ASCII digits only.
    static func digits(_ value: String) -> String {
        String(value.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init))
    }

    /// Cleans an OCR'd phone number for display; `+998XXXXXXXXX` in any spacing becomes `+998 XX XXX XX XX`.
    static func display(_ raw: String) -> String {
        let digits = digits(raw)
        if digits.count == 12, digits.hasPrefix("998") {
            let chars = Array(digits)
            func group(_ range: Range<Int>) -> String { String(chars[range]) }
            return "+998 \(group(3..<5)) \(group(5..<8)) \(group(8..<10)) \(group(10..<12))"
        }
        return raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Whether a number looks like an Uzbek mobile (`+998 9x…`, `33`, `50`, `77`, `88`, `20`).
    static func isUzbekMobile(_ value: String) -> Bool {
        let digits = digits(value)
        let local: Substring
        if digits.count == 12, digits.hasPrefix("998") {
            local = digits.dropFirst(3)
        } else if digits.count == 9 {
            local = Substring(digits)
        } else {
            return false
        }
        return mobilePrefixes.contains(String(local.prefix(2)))
    }

    /// Plausible length for a phone number (local 7 digits … E.164 15 digits).
    static func isPlausible(_ value: String) -> Bool {
        (7...15).contains(digits(value).count)
    }

    private static let mobilePrefixes: Set<String> = ["20", "33", "50", "77", "88", "90", "91", "93", "94", "95", "97", "98", "99"]
}
