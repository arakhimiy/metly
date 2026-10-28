import Foundation
import MetlyCapture
import MetlyCore
import MetlyData

/// How a reminder's "Reply Via" channel opens the other app (Telegram / Mail / Phone).
enum ChannelLink {
    /// What a channel action opens: the app URL first, then the fallback when it can't be opened.
    struct Target: Equatable {
        var primary: URL
        var fallback: URL?
        /// Telegram opens the chat by phone number (no username saved).
        var isTelegramByPhone = false
    }

    /// Button label on Home rows (PLAN Q40: "Telegram", "Mail", "Call").
    static func actionTitle(_ channel: FollowUpChannel) -> String {
        switch channel {
        case .telegram: String(localized: "Telegram")
        case .email: String(localized: "Mail")
        case .call: String(localized: "Call")
        }
    }

    /// The URLs for `channel` with `person`'s saved values, nil when the channel can't reach them.
    /// • Telegram: the username, else the mobile number (`tg://resolve?phone=`, then `t.me/+…`).
    /// • Call: the mobile number, else the primary one.
    static func target(_ channel: FollowUpChannel, for person: Connection?) -> Target? {
        guard let person else { return nil }
        switch channel {
        case .telegram:
            guard let telegram = person.telegramTarget, let app = telegram.appURL else { return nil }
            return Target(primary: app, fallback: telegram.webURL, isTelegramByPhone: telegram.isByPhone)
        case .email:
            return ContactLinks.mail(person.email).map { Target(primary: $0) }
        case .call:
            return callNumber(for: person).flatMap(ContactLinks.call).map { Target(primary: $0) }
        }
    }

    /// The number a reminder's Call uses: the first dialable mobile number, else the first dialable one.
    static func callNumber(for person: Connection) -> String? {
        person.phonesForMessaging.first { ContactLinks.call($0.value) != nil }?.value
    }

    static func canOpen(_ channel: FollowUpChannel, for person: Connection?) -> Bool {
        target(channel, for: person) != nil
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
        case .telegram: String(localized: "\(firstName) has no Telegram username or mobile number saved.")
        case .email: String(localized: "\(firstName) has no email address saved.")
        case .call: String(localized: "\(firstName) has no phone number saved.")
        }
    }
}
