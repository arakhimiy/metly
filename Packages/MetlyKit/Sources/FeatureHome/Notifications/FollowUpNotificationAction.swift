import Foundation
import UserNotifications

/// What a notification response asks the app to do (parsed off the main actor, Sendable).
nonisolated public enum FollowUpNotificationAction: Equatable, Sendable {
    /// Tap on a follow-up notification → FOLLOWUPS (SPEC §2.3 "PUSH_FOLLOWUP → FOLLOWUPS").
    case openFollowUps(followUpID: UUID?)
    /// "Open Telegram / Mail / Call" (foreground action).
    case openChannel(followUpID: UUID)
    /// "Snooze 1 Day" (handled in the background).
    case snooze(followUpID: UUID)
    /// Another notification carrying a `link` (`tanishly://…`) — routed through the app's deep links.
    case openLink(URL)
    /// Dismissed, or nothing we understand.
    case ignore

    init(actionIdentifier: String, categoryIdentifier: String, requestIdentifier: String,
                     userInfo: [AnyHashable: Any]) {
        let followUpID = (userInfo[FollowUpNotificationPayload.UserInfoKey.followUpID] as? String).flatMap(UUID.init(uuidString:))
            ?? FollowUpNotificationPayload.followUpID(fromIdentifier: requestIdentifier)
        let link = (userInfo[FollowUpNotificationPayload.UserInfoKey.link] as? String).flatMap(URL.init(string:))
        let isFollowUp = FollowUpNotificationCategory.isFollowUpCategory(categoryIdentifier) || followUpID != nil

        switch actionIdentifier {
        case UNNotificationDismissActionIdentifier:
            self = .ignore
        case FollowUpNotificationCategory.snoozeAction:
            self = followUpID.map { .snooze(followUpID: $0) } ?? .ignore
        case FollowUpNotificationCategory.openChannelAction:
            self = followUpID.map { .openChannel(followUpID: $0) } ?? .openFollowUps(followUpID: nil)
        default:
            if isFollowUp {
                self = .openFollowUps(followUpID: followUpID)
            } else if let link {
                self = .openLink(link)
            } else {
                self = .ignore
            }
        }
    }
}
