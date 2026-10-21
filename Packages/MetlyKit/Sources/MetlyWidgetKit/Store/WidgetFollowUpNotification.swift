import Foundation
import UserNotifications

/// The local PUSH_FOLLOWUP notification the app schedules for an open follow-up (FeatureHome's
/// `FollowUpNotificationScheduler`: one request per reminder, identifier `followup.{UUID}`).
///
/// A widget "Done" tap only queues the completion — the app applies it the next time it runs — so the
/// widget withdraws the reminder's notification itself; otherwise it could still fire. MetlyWidgetKit
/// can't import FeatureHome, so the identifier scheme is repeated here; tests in both modules pin the
/// same literal format (`followup.` + uppercase UUID string).
nonisolated public enum WidgetFollowUpNotification {
    public static let identifierPrefix = "followup."

    public static func identifier(for followUpID: UUID) -> String {
        identifierPrefix + followUpID.uuidString
    }
}

/// The part of `UNUserNotificationCenter` a widget "Done" tap needs (a recording fake in tests).
nonisolated public protocol WidgetNotificationCenter: Sendable {
    /// Removes pending and delivered notifications with these identifiers.
    func removeNotifications(withIdentifiers identifiers: [String])
}

/// The app's notification center (app extensions share their containing app's). Does nothing outside
/// an app or extension bundle, where `UNUserNotificationCenter.current()` traps (unit-test runner).
nonisolated public struct SystemWidgetNotificationCenter: WidgetNotificationCenter {
    public init() {}

    public func removeNotifications(withIdentifiers identifiers: [String]) {
        guard !identifiers.isEmpty, ["app", "appex"].contains(Bundle.main.bundleURL.pathExtension) else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
    }
}
