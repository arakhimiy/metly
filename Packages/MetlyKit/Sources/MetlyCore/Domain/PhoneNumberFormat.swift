import Foundation

/// Spaces a phone number the way people write it in its country, while it's typed:
/// `+998901234567` → `+998 90 123 45 67`, `+7 9123456789` → `+7 912 345 67 89`. A number typed without its
/// country code is grouped like a local number (Uzbek `90 123 45 67`) and gets `+998` once the user leaves
/// the field (`normalized`), when it is clearly Uzbek.
public nonisolated enum PhoneNumberFormat {
    /// National grouping per country calling code (digits after the code).
    static let groups: [String: [Int]] = [
        "998": [2, 3, 2, 2],   // Uzbekistan
        "7": [3, 3, 2, 2],     // Russia, Kazakhstan
        "992": [2, 3, 4],      // Tajikistan
        "996": [3, 3, 3],      // Kyrgyzstan
        "993": [2, 2, 2, 2],   // Turkmenistan
        "994": [2, 3, 2, 2],   // Azerbaijan
        "90": [3, 3, 2, 2],    // Türkiye
        "82": [2, 4, 4],       // South Korea
        "1": [3, 3, 4],        // US, Canada
        "44": [4, 6],          // UK
        "49": [3, 4, 4],       // Germany
        "971": [2, 3, 4],      // UAE
        "86": [3, 4, 4],       // China
    ]

    /// Two-digit calling codes (ITU zones 2–9); "1" and "7" are the one-digit ones; the rest have three.
    private static let twoDigitCodes: Set<String> = [
        "20", "27", "30", "31", "32", "33", "34", "36", "39", "40", "41", "43", "44", "45", "46", "47", "48", "49",
        "51", "52", "53", "54", "55", "56", "57", "58", "60", "61", "62", "63", "64", "65", "66", "81", "82", "84",
        "86", "90", "91", "92", "93", "94", "95", "98",
    ]

    /// Uzbek operator and area codes: a 9-digit number starting with one of these is Uzbek.
    static let uzbekPrefixes: Set<String> = [
        "20", "33", "50", "77", "88", "90", "91", "93", "94", "95", "97", "98", "99",
        "55", "61", "62", "65", "66", "67", "69", "70", "71", "72", "73", "74", "75", "76", "78", "79",
    ]

    /// The number as typed so far, spaced. Keeps a leading "+" (or "00" read as "+") and digits only, at most
    /// 15 of them (E.164).
    public static func asYouType(_ input: String, region: String? = Locale.current.region?.identifier) -> String {
        var text = input.trimmingCharacters(in: .whitespaces)
        var hasPlus = text.hasPrefix("+")
        if !hasPlus, text.hasPrefix("00") {
            hasPlus = true
            text.removeFirst(2)
        }
        let digits = String(text.filter { $0.isASCII && $0.isNumber }.prefix(15))
        if hasPlus { return international(digits) }
        if digits.count > 9, digits.hasPrefix("998") { return international(digits) }
        if isLocalUzbek(digits, region: region) { return grouped(digits, by: groups["998"]!) }
        return grouped(digits, by: [3, 3, 2, 2, 2, 2])
    }

    /// When the user leaves the field: spaced, and a clearly Uzbek local number gets its `+998`.
    public static func normalized(_ input: String, region: String? = Locale.current.region?.identifier) -> String {
        let spaced = asYouType(input, region: region)
        let digits = spaced.filter(\.isNumber)
        if !spaced.hasPrefix("+"), digits.count == 9, isLocalUzbek(digits, region: region) {
            return international("998" + digits)
        }
        return spaced
    }

    private static func isLocalUzbek(_ digits: String, region: String?) -> Bool {
        guard digits.count <= 9 else { return false }
        if region == "UZ" { return true }
        return digits.count >= 2 && uzbekPrefixes.contains(String(digits.prefix(2)))
    }

    private static func international(_ digits: String) -> String {
        guard !digits.isEmpty else { return "+" }
        let code: String
        if let one = digits.first.map(String.init), one == "1" || one == "7" {
            code = one
        } else if digits.count >= 2, twoDigitCodes.contains(String(digits.prefix(2))) {
            code = String(digits.prefix(2))
        } else {
            code = String(digits.prefix(3))
        }
        let rest = String(digits.dropFirst(code.count))
        let national = grouped(rest, by: groups[code] ?? [3, 3, 3, 3])
        return national.isEmpty ? "+\(code)" : "+\(code) \(national)"
    }

    /// Digits split into groups of the given sizes; anything past them stays in the last group.
    private static func grouped(_ digits: String, by sizes: [Int]) -> String {
        var parts: [String] = []
        var rest = Substring(digits)
        for (index, size) in sizes.enumerated() where !rest.isEmpty {
            let take = index == sizes.count - 1 ? rest.count : size
            parts.append(String(rest.prefix(take)))
            rest = rest.dropFirst(take)
        }
        return parts.joined(separator: " ")
    }
}
