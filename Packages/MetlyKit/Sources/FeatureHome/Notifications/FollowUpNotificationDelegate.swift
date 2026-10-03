import Foundation
import UserNotifications

/// `UNUserNotificationCenterDelegate` that parses responses where they arrive and hands a
/// Sendable `FollowUpNotificationAction` to the main-actor scheduler.
nonisolated final class FollowUpNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    typealias Handler = @MainActor @Sendable (FollowUpNotificationAction) async -> Void

    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    /// Show reminders (and any other notification) as a banner while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    /// Taps and action buttons. The system keeps the app running until this returns, so
    /// "Snooze 1 Day" finishes saving (and rescheduling) in the background.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        let action = FollowUpNotificationAction(actionIdentifier: response.actionIdentifier,
                                                categoryIdentifier: request.content.categoryIdentifier,
                                                requestIdentifier: request.identifier,
                                                userInfo: request.content.userInfo)
        await handler(action)
    }
}
