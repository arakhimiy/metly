import Foundation
import MetlyCore

/// Phone helpers for OCR results (Uzbek numbers get the familiar `+998 90 123 45 67` grouping).
nonisolated enum PhoneFormat {
    /// ASCII digits only.
    static func digits(_ value: String) -> String {
        String(value.unicodeScalars.filter { ("0"..."9").contains($0) }.map(Character.init))
    }

    /// Last 9 digits — "+998 90 123 45 67" and "90 123-45-67" are the same number.
    static func key(_ value: String) -> String {
        String(digits(value).suffix(9))
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
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;.-"))
    }

    /// Whether a number looks like an Uzbek mobile (`+998 9x…`, `33`, `50`, `77`, `88`, `20`).
    static func isUzbekMobile(_ value: String) -> Bool {
        uzbekCode(of: value).map(mobilePrefixes.contains) ?? false
    }

    /// The kind of number its prefix gives away, when it does: Uzbek mobile operator codes vs.
    /// landline area codes, Russian `+7 9xx` mobiles vs. `+7 3xx/4xx/8xx` landlines,
    /// Kazakh `+7 7xx` mobiles.
    static func inferredLabel(_ value: String) -> PhoneLabel? {
        if let code = uzbekCode(of: value) {
            if mobilePrefixes.contains(code) { return .mobile }
            if landlinePrefixes.contains(code) { return .work }
            return nil
        }
        let digits = digits(value)
        if digits.count == 11, digits.hasPrefix("7") || (digits.hasPrefix("8") && value.contains("(")) {
            let code = Array(digits.dropFirst().prefix(2))
            switch code.first {
            case "9": return .mobile
            case "7": return "045678".contains(code.last ?? " ") ? .mobile : .work
            case "3", "4", "8": return .work
            default: return nil
            }
        }
        return nil
    }

    /// Plausible length for a phone number (local 7 digits … E.164 15 digits).
    static func isPlausible(_ value: String) -> Bool {
        (7...15).contains(digits(value).count)
    }

    /// Two-digit operator / area code of an Uzbek number (`+998 XX …` or a 9-digit local number).
    private static func uzbekCode(of value: String) -> String? {
        let digits = digits(value)
        if digits.count == 12, digits.hasPrefix("998") { return String(digits.dropFirst(3).prefix(2)) }
        if digits.count == 9 { return String(digits.prefix(2)) }
        return nil
    }

    private static let mobilePrefixes: Set<String> = ["20", "33", "50", "77", "88", "90", "91", "93", "94", "95", "97", "98", "99"]
    private static let landlinePrefixes: Set<String> = [
        "55", "61", "62", "65", "66", "67", "69", "70", "71", "72", "73", "74", "75", "76", "78", "79",
    ]
}
