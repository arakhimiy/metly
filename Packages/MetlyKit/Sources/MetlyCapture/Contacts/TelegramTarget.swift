import Foundation

/// Who a Telegram action opens: the saved username, or — when there is none — the person's mobile number
/// (`tg://resolve?phone=`). Telegram shows a number's account only if that person's privacy settings
/// ("Who can find me by my number") allow it, so by-phone actions say so in their copy.
nonisolated public enum TelegramTarget: Hashable, Sendable {
    case username(String)
    /// International digits without "+" (`998901234567`).
    case phone(String)

    /// The username wins; otherwise the first phone Telegram can use (pass mobile numbers first).
    public init?(username: String, phones: [String]) {
        if let handle = ContactLinks.telegramHandle(username) {
            self = .username(handle)
        } else if let digits = phones.lazy.compactMap(TelegramPhone.digits(from:)).first {
            self = .phone(digits)
        } else {
            return nil
        }
    }

    public var isByPhone: Bool {
        if case .phone = self { return true }
        return false
    }

    /// Telegram app link — open it first, fall back to `webURL` when Telegram isn't installed.
    public var appURL: URL? {
        var components = URLComponents()
        components.scheme = "tg"
        components.host = "resolve"
        switch self {
        case .username(let handle): components.queryItems = [URLQueryItem(name: "domain", value: handle)]
        case .phone(let digits): components.queryItems = [URLQueryItem(name: "phone", value: digits)]
        }
        return components.url
    }

    /// `https://t.me/{username}` or `https://t.me/+{digits}` — works without the Telegram app.
    public var webURL: URL? {
        switch self {
        case .username(let handle): URL(string: "https://t.me/\(handle)")
        case .phone(let digits): URL(string: "https://t.me/+\(digits)")
        }
    }

    /// Footnote for by-phone actions.
    public static let byPhoneNote = String(localized: "Opens Telegram by phone number. Telegram finds them only if their privacy settings allow it.")
}
