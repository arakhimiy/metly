import Foundation
import MetlyCapture
import MetlyCore
import MetlyData

/// How a reminder's "Reply Via" channel opens the other app (Telegram / Mail / Phone).
enum ChannelLink {
    /// Button label on Home rows (PLAN Q40: "Telegram", "Mail", "Call").
    static func actionTitle(_ channel: FollowUpChannel) -> String {
        switch channel {
        case .telegram: String(localized: "Telegram")
        case .email: String(localized: "Mail")
        case .call: String(localized: "Call")
        }
    }

    /// The contact value a channel uses.
    static func value(for channel: FollowUpChannel, of person: Connection?) -> String {
        guard let person else { return "" }
        return switch channel {
        case .telegram: person.telegram
        case .email: person.email
        case .call: person.phone
        }
    }

    /// App URL to open first (`tg://`, `mailto:`, `tel:`), nil when the value can't be used.
    static func primaryURL(_ channel: FollowUpChannel, value: String) -> URL? {
        switch channel {
        case .telegram: ContactLinks.telegramApp(value)
        case .email: ContactLinks.mail(value)
        case .call: ContactLinks.call(value)
        }
    }

    /// Used when the primary URL can't be opened (no Telegram app → t.me in Safari).
    static func fallbackURL(_ channel: FollowUpChannel, value: String) -> URL? {
        channel == .telegram ? ContactLinks.telegramWeb(value) : nil
    }

    static func canOpen(_ channel: FollowUpChannel, for person: Connection?) -> Bool {
        primaryURL(channel, value: value(for: channel, of: person)) != nil
    }

    /// Channels that have a usable value for `person` (all of them when nothing is known,
    /// so a reminder for a person without contact details can still pick a channel).
    static func availableChannels(for person: Connection?) -> Set<FollowUpChannel> {
        let usable = Set(FollowUpChannel.allCases.filter { canOpen($0, for: person) })
        return usable.isEmpty ? Set(FollowUpChannel.allCases) : usable
    }

    /// "Kamila has no phone number saved." for a channel without a value.
    static func missingValueNote(_ channel: FollowUpChannel, firstName: String) -> String {
        switch channel {
        case .telegram: String(localized: "\(firstName) has no Telegram username saved.")
        case .email: String(localized: "\(firstName) has no email address saved.")
        case .call: String(localized: "\(firstName) has no phone number saved.")
        }
    }
}
