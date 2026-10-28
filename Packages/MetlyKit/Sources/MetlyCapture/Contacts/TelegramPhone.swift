import Foundation

/// Turns a stored phone number into the international digits Telegram resolves (`998901234567` for
/// `tg://resolve?phone=` and `https://t.me/+998901234567`).
///
/// Telegram finds an account by number only in international form, and only for mobile numbers. So:
/// • "+998 90 123 45 67", "00998 90…", "998 90…" — used as written (Uzbek numbers must be mobile).
/// • No country code: a 9-digit Uzbek mobile number ("90 123-45-67") or one with the old trunk prefix
///   ("8 (90) 123-45-67") gets +998. Anything else without a country code is not guessed.
/// • Known landlines are skipped: Uzbek area codes (71 Tashkent, 66 Samarkand…), Russian geographic codes
///   (+7 495…), Kazakh city codes (+7 727…).
nonisolated public enum TelegramPhone {
    /// Uzbek operator codes (first two of the nine national digits) that are mobile networks.
    static let uzbekMobileCodes: Set<String> = ["20", "33", "50", "77", "88", "90", "91", "93", "94", "95", "97", "98", "99"]

    /// International digits without "+", or nil when the number can't find someone on Telegram.
    public static func digits(from raw: String) -> String? {
        // "+998 71 200-00-00 (ext. 12)", "доб. 3": ignore everything from the first letter on.
        let number = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix { !$0.isLetter })
        var digits = number.filter(\.isASCIIDigit)
        // "+998…", "(+998) …"
        var isInternational = number.first { $0 != "(" && !$0.isWhitespace } == "+"
        if !isInternational, digits.hasPrefix("00") {
            digits.removeFirst(2)
            isInternational = true
        }

        if isInternational {
            return international(digits)
        }
        switch digits.count {
        case 9:
            return uzbekMobile(national: digits)
        case 10 where digits.hasPrefix("8"):
            return uzbekMobile(national: String(digits.dropFirst()))
        case 12 where digits.hasPrefix("998"):
            return uzbekMobile(national: String(digits.dropFirst(3)))
        default:
            return nil
        }
    }

    // MARK: Private

    private static func international(_ digits: String) -> String? {
        // E.164: country code + subscriber number, 8…15 digits.
        guard (8...15).contains(digits.count) else { return nil }
        if digits.hasPrefix("998") {
            guard digits.count == 12 else { return nil }
            return uzbekMobile(national: String(digits.dropFirst(3)))
        }
        if digits.hasPrefix("7") {
            guard digits.count == 11 else { return nil }
            return isRussianOrKazakhMobile(national: String(digits.dropFirst())) ? digits : nil
        }
        return digits
    }

    private static func uzbekMobile(national: String) -> String? {
        guard national.count == 9, national.allSatisfy(\.isASCIIDigit),
              uzbekMobileCodes.contains(String(national.prefix(2))) else { return nil }
        return "998" + national
    }

    /// +7: Russian mobiles start with 9 (landlines with 3, 4, 8); Kazakh mobiles with 70x, 74x–77x
    /// (city codes 71x / 72x are landlines).
    private static func isRussianOrKazakhMobile(national: String) -> Bool {
        let first = national.first
        if first == "9" { return true }
        guard first == "7", national.count > 1 else { return false }
        let second = national[national.index(after: national.startIndex)]
        return "04567".contains(second)
    }
}

private extension Character {
    nonisolated var isASCIIDigit: Bool { isASCII && isNumber }
}
