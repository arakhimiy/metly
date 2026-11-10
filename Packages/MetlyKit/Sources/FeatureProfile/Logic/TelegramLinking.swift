import Foundation
import MetlyCore

/// Deep link that starts the reminder bot (`@TanishlyBot`) with a linking token.
nonisolated enum TelegramLinking {
    /// Off until the bot runs on the server (TELEGRAM_BOT_TOKEN) and linking uses the API token below:
    /// until then "Telegram Bot" would look connected while reminders went nowhere.
    static let isAvailable = false

    /// TODO(backend): replace with a one-time token issued by the API (e.g. `POST /v1/me/telegram/link-token`).
    /// The bot receives it via `/start <token>`, links the chat to the account and the server flips
    /// `notificationPrefs.telegramLinked`, which reaches the app through sync. Until that exists the
    /// app marks the bot as linked optimistically once Telegram opens (prototype behaviour).
    static func placeholderToken() -> String {
        UUID().uuidString.replacing("-", with: "").lowercased()
    }

    /// `https://t.me/TanishlyBot?start={token}` — Telegram allows `[A-Za-z0-9_-]{1,64}`.
    static func startURL(token: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "t.me"
        components.path = "/\(Brand.telegramBot)"
        components.queryItems = [URLQueryItem(name: "start", value: token)]
        return components.url
    }

    static var botHandle: String { "@\(Brand.telegramBot)" }
}
