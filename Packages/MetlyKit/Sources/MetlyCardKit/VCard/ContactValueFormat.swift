import Foundation
import MetlyCore

/// Converts between how contact values are typed/displayed in the app ("@handle", "in/handle",
/// "site.com") and the URLs written to vCards.
public enum ContactValueFormat {
    // MARK: Telegram

    /// Bare username from "@user", "user", "t.me/user", "https://t.me/user?start=x", "telegram.me/user".
    public static func telegramUsername(from value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://", "tg://resolve?domain="] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        for host in ["www.t.me/", "t.me/", "telegram.me/", "telegram.dog/"] where text.lowercased().hasPrefix(host) {
            text = String(text.dropFirst(host.count))
        }
        if text.hasPrefix("@") { text.removeFirst() }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" && $0 != "&" })
        guard !text.isEmpty, text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else { return nil }
        return text
    }

    public static func telegramURL(username: String) -> URL? {
        URL(string: "https://t.me/\(username)")
    }

    /// "@user" as shown in the app.
    public static func telegramDisplay(username: String) -> String { "@\(username)" }

    // MARK: WhatsApp / Instagram

    /// `https://wa.me/{digits}` from a phone number (or a wa.me link).
    public static func whatsAppURL(from value: String) -> URL? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://wa.me/", "http://wa.me/", "wa.me/"] where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
        }
        let digits = text.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "https://wa.me/\(digits)")
    }

    /// Bare username from "@user", "user", "instagram.com/user/" or a full URL.
    public static func instagramUsername(from value: String) -> String? {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) { text = String(text.dropFirst(prefix.count)) }
        for host in ["www.instagram.com/", "instagram.com/", "instagr.am/"] where text.lowercased().hasPrefix(host) {
            text = String(text.dropFirst(host.count))
        }
        if text.hasPrefix("@") { text.removeFirst() }
        text = String(text.prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        guard !text.isEmpty, text.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" || $0 == "." }) else { return nil }
        return text
    }

    public static func instagramURL(username: String) -> URL? {
        URL(string: "https://instagram.com/\(username)")
    }

    // MARK: LinkedIn

    /// Profile URL from "in/user", "user", "linkedin.com/in/user" or a full URL.
    public static func linkedInURL(from value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return URL(string: text) }
        if lower.contains("linkedin.com") { return URL(string: "https://\(text)") }
        let path = text.hasPrefix("/") ? String(text.dropFirst()) : text
        if lower.hasPrefix("in/") || lower.hasPrefix("company/") || lower.hasPrefix("pub/") {
            return URL(string: "https://www.linkedin.com/\(path)")
        }
        return URL(string: "https://www.linkedin.com/in/\(path)")
    }

    /// "in/user" for profile URLs, otherwise the URL without scheme.
    public static func linkedInDisplay(from url: URL) -> String {
        let path = url.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if path.lowercased().hasPrefix("in/") || path.lowercased().hasPrefix("company/") { return path }
        return websiteDisplay(from: url.absoluteString)
    }

    // MARK: Website

    /// Adds `https://` when the value has no scheme.
    public static func websiteURL(from value: String) -> URL? {
        let text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) != nil { return URL(string: text) }
        return URL(string: "https://\(text)")
    }

    /// "site.com/path" — scheme, leading "www." and trailing slash removed.
    public static func websiteDisplay(from value: String) -> String {
        var text = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = text.range(of: "^[a-zA-Z][a-zA-Z0-9+.-]*://", options: .regularExpression) {
            text.removeSubrange(range)
        }
        if text.lowercased().hasPrefix("www.") { text.removeFirst(4) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    // MARK: Classification

    enum URLKind: Equatable { case telegram(String), linkedIn(URL), metlyCard, website(URL) }

    static func classify(_ value: String) -> URLKind? {
        guard let url = websiteURL(from: value), let host = url.host()?.lowercased() else { return nil }
        if ["t.me", "www.t.me", "telegram.me", "telegram.dog"].contains(host) {
            return telegramUsername(from: value).map(URLKind.telegram)
        }
        if host == "linkedin.com" || host.hasSuffix(".linkedin.com") { return .linkedIn(url) }
        if host == Brand.linkHost { return .metlyCard }
        return .website(url)
    }
}
