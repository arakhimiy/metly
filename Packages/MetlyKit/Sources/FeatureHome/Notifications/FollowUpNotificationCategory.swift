import Foundation
import MetlyCore
import UserNotifications

/// Notification categories for PUSH_FOLLOWUP (SPEC §7.3): "Open {channel}" (foreground) + "Snooze 1 Day" (background).
/// Category actions are static, so there is one category per channel plus a plain one for
/// reminders whose person has no usable value for the chosen channel.
nonisolated enum FollowUpNotificationCategory {
    static let base = "FOLLOW_UP"
    static let openChannelAction = "FOLLOW_UP_OPEN_CHANNEL"
    static let snoozeAction = "FOLLOW_UP_SNOOZE_1D"

    /// "FOLLOW_UP" or "FOLLOW_UP_TELEGRAM" / "FOLLOW_UP_EMAIL" / "FOLLOW_UP_CALL".
    static func identifier(for channel: FollowUpChannel?) -> String {
        guard let channel else { return base }
        return "\(base)_\(channel.rawValue.uppercased())"
    }

    static var allIdentifiers: [String] {
        [identifier(for: nil)] + FollowUpChannel.allCases.map { identifier(for: $0) }
    }

    static func isFollowUpCategory(_ identifier: String) -> Bool {
        identifier == base || identifier.hasPrefix(base + "_")
    }

    static func openActionTitle(_ channel: FollowUpChannel) -> String {
        switch channel {
        case .telegram: String(localized: "Open Telegram")
        case .email: String(localized: "Open Mail")
        case .call: String(localized: "Call")
        }
    }

    static func openActionIcon(_ channel: FollowUpChannel) -> String {
        channel.symbolName
    }

    static func makeCategories() -> Set<UNNotificationCategory> {
        let snooze = UNNotificationAction(identifier: snoozeAction, title: String(localized: "Snooze 1 Day"),
                                          options: [], icon: UNNotificationActionIcon(systemImageName: "clock.arrow.circlepath"))
        var categories: Set<UNNotificationCategory> = [
            UNNotificationCategory(identifier: identifier(for: nil), actions: [snooze], intentIdentifiers: [], options: []),
        ]
        for channel in FollowUpChannel.allCases {
            let open = UNNotificationAction(identifier: openChannelAction, title: openActionTitle(channel),
                                            options: [.foreground],
                                            icon: UNNotificationActionIcon(systemImageName: openActionIcon(channel)))
            categories.insert(UNNotificationCategory(identifier: identifier(for: channel), actions: [open, snooze],
                                                     intentIdentifiers: [], options: []))
        }
        return categories
    }
}
