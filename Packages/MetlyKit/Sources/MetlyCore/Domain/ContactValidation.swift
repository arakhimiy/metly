import Foundation

/// What a contact value may look like, per kind — checked where it's typed (a red note under the field) and
/// before it leaves the device: an entry that isn't valid stays on this phone until it's fixed (never synced,
/// never on a card).
public nonisolated enum ContactValidation {
    /// Why `value` isn't a valid `kind`, or nil when it is (empty values are "not filled", not invalid).
    public static func problem(_ value: String, for kind: ContactFieldKind) -> String? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        switch kind {
        case .phone, .whatsapp:
            let digits = text.filter(\.isNumber).count
            guard text.allSatisfy({ $0.isNumber || " +-()".contains($0) }), (7...15).contains(digits) else {
                return String(localized: "Enter a full phone number, like +998 90 123 45 67.", bundle: .appStrings)
            }
        case .email:
            guard text.wholeMatch(of: /[A-Za-z0-9._%+\-]+@[A-Za-z0-9\-]+(\.[A-Za-z0-9\-]+)*\.[A-Za-z]{2,}/) != nil else {
                return String(localized: "Enter an email address, like name@example.com.", bundle: .appStrings)
            }
        case .telegram:
            guard handle(text).wholeMatch(of: /[A-Za-z0-9_.]{3,32}/) != nil else {
                return String(localized: "Enter a Telegram username, like @username.", bundle: .appStrings)
            }
        case .instagram:
            guard handle(text).wholeMatch(of: /[A-Za-z0-9_.]{1,30}/) != nil else {
                return String(localized: "Enter an Instagram username, like @username.", bundle: .appStrings)
            }
        case .website:
            guard !text.contains(" "), let host = host(of: text), host.contains("."), !host.hasSuffix(".") else {
                return String(localized: "Enter a website, like example.com.", bundle: .appStrings)
            }
        case .address:
            guard text.count >= 5 else {
                return String(localized: "Enter the full address, like street, building and city.", bundle: .appStrings)
            }
        case .linkedin:
            guard !text.contains(" "), text.count >= 3 else {
                return String(localized: "Enter your LinkedIn profile, like in/username.", bundle: .appStrings)
            }
        }
        return nil
    }

    public static func isValid(_ value: String, for kind: ContactFieldKind) -> Bool {
        problem(value, for: kind) == nil
    }

    /// "@user", "t.me/user", "instagram.com/user/" → "user".
    private static func handle(_ text: String) -> String {
        var value = text
        for prefix in ["https://", "http://", "www.", "t.me/", "telegram.me/", "instagram.com/", "instagr.am/", "@"]
        where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        while value.hasSuffix("/") { value.removeLast() }
        return value
    }

    private static func host(of text: String) -> String? {
        let string = text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) == nil ? "https://\(text)" : text
        return URL(string: string)?.host()
    }
}

public extension ContactEntry {
    /// Filled and well-formed for its kind (see `ContactValidation`).
    var isValid: Bool { !isEmpty && ContactValidation.isValid(value, for: kind) }
}
