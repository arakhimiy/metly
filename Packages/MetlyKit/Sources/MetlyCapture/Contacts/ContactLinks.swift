import Foundation
import MetlyCore

/// URLs for contacting someone from their stored values (Message / Call / Mail actions, follow-up channels).
nonisolated public enum ContactLinks {
    /// "@aziza.k", "t.me/aziza_k", "https://t.me/aziza_k" → "aziza.k". Nil when empty.
    public static func telegramHandle(_ value: String) -> String? {
        var handle = value.trimmed
        for prefix in ["https://", "http://", "www.", "t.me/", "telegram.me/", "@"] where handle.lowercased().hasPrefix(prefix) {
            handle = String(handle.dropFirst(prefix.count))
        }
        handle = handle.split(separator: "/").first.map(String.init) ?? ""
        handle = handle.split(separator: "?").first.map(String.init) ?? ""
        return handle.isEmpty ? nil : handle
    }

    /// Telegram app link (`tg://resolve?domain=`) — open it first, fall back to `telegramWeb`.
    public static func telegramApp(_ value: String) -> URL? {
        guard let handle = telegramHandle(value) else { return nil }
        var components = URLComponents()
        components.scheme = "tg"
        components.host = "resolve"
        components.queryItems = [URLQueryItem(name: "domain", value: handle)]
        return components.url
    }

    /// `https://t.me/{handle}` — works without the Telegram app.
    public static func telegramWeb(_ value: String) -> URL? {
        telegramHandle(value).flatMap { URL(string: "https://t.me/\($0)") }
    }

    /// Telegram by phone number (`tg://resolve?phone=998901234567`) — nil when Telegram can't use the number
    /// (no country code and not Uzbek, or a landline). See `TelegramPhone`.
    public static func telegramApp(phone: String) -> URL? {
        TelegramPhone.digits(from: phone).flatMap { TelegramTarget.phone($0).appURL }
    }

    /// `https://t.me/+998901234567` — the by-phone fallback without the Telegram app.
    public static func telegramWeb(phone: String) -> URL? {
        TelegramPhone.digits(from: phone).flatMap { TelegramTarget.phone($0).webURL }
    }

    /// Username first, else the first usable phone (pass mobile numbers first).
    public static func telegram(username: String, phones: [String]) -> TelegramTarget? {
        TelegramTarget(username: username, phones: phones)
    }

    /// Digits with an optional leading "+".
    public static func dialable(_ phone: String) -> String? {
        let trimmed = phone.trimmed
        let digits = trimmed.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return trimmed.hasPrefix("+") ? "+" + digits : digits
    }

    public static func call(_ phone: String) -> URL? {
        dialable(phone).flatMap { URL(string: "tel:\($0)") }
    }

    public static func sms(_ phone: String) -> URL? {
        dialable(phone).flatMap { URL(string: "sms:\($0)") }
    }

    public static func mail(_ email: String) -> URL? {
        let address = email.trimmed
        guard address.contains("@"), !address.contains(" ") else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        return components.url
    }

    /// "aziza.design" → https://aziza.design
    public static func website(_ value: String) -> URL? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let lower = trimmed.lowercased()
        let string = lower.hasPrefix("http://") || lower.hasPrefix("https://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: string), url.host() != nil else { return nil }
        return url
    }

    /// `https://wa.me/{digits}` — opens WhatsApp (or its web page) on that number. Nil without digits.
    public static func whatsApp(_ phone: String) -> URL? {
        var value = phone.trimmed
        for prefix in ["https://wa.me/", "http://wa.me/", "wa.me/"] where value.lowercased().hasPrefix(prefix) {
            value = String(value.dropFirst(prefix.count))
        }
        let digits = value.filter(\.isNumber)
        return digits.isEmpty ? nil : URL(string: "https://wa.me/\(digits)")
    }

    /// "@aziza.k", "aziza.k", "instagram.com/aziza.k/" or a full URL → "aziza.k". Nil when empty.
    public static func instagramHandle(_ value: String) -> String? {
        var handle = value.trimmed
        for prefix in ["https://", "http://", "www.", "instagram.com/", "instagr.am/", "@"] where handle.lowercased().hasPrefix(prefix) {
            handle = String(handle.dropFirst(prefix.count))
        }
        handle = handle.split(separator: "/").first.map(String.init) ?? ""
        handle = handle.split(separator: "?").first.map(String.init) ?? ""
        return handle.isEmpty || handle.contains(" ") ? nil : handle
    }

    /// `https://instagram.com/{handle}`.
    public static func instagram(_ value: String) -> URL? {
        instagramHandle(value).flatMap { URL(string: "https://instagram.com/\($0)") }
    }

    /// Where tapping an entry goes (web links, so they work without the app installed).
    public static func url(for kind: ContactFieldKind, value: String) -> URL? {
        switch kind {
        case .phone: call(value)
        case .whatsapp: whatsApp(value)
        case .telegram: telegramWeb(value)
        case .instagram: instagram(value)
        case .email: mail(value)
        case .website: website(value)
        case .linkedin: linkedIn(value)
        }
    }

    /// "in/azizakarimova", "linkedin.com/in/…" or a full URL → https://www.linkedin.com/in/…
    public static func linkedIn(_ value: String) -> URL? {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if trimmed.lowercased().contains("linkedin.com") { return website(trimmed) }
        let path = trimmed.hasPrefix("in/") ? trimmed : "in/\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "@/")))"
        return URL(string: "https://www.linkedin.com/\(path)")
    }
}
