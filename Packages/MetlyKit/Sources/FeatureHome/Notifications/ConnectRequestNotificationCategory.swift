import Foundation
import UserNotifications

/// PUSH_CONNECT_REQUEST ("Aziza wants to swap cards"): Accept opens the app on CONNECTED to capture
/// context; Decline answers quietly in the background. Both need the phone unlocked.
nonisolated enum ConnectRequestNotificationCategory {
    static let identifier = "CONNECT_REQUEST"
    static let acceptAction = "CONNECT_REQUEST_ACCEPT"
    static let declineAction = "CONNECT_REQUEST_DECLINE"
    /// Push payload key (backend `data.requestId`).
    static let requestIDKey = "requestId"

    static func makeCategory() -> UNNotificationCategory {
        let accept = UNNotificationAction(identifier: acceptAction, title: String(localized: "Accept"),
                                          options: [.foreground, .authenticationRequired],
                                          icon: UNNotificationActionIcon(systemImageName: "checkmark.circle"))
        let decline = UNNotificationAction(identifier: declineAction, title: String(localized: "Decline"),
                                           options: [.destructive, .authenticationRequired],
                                           icon: UNNotificationActionIcon(systemImageName: "xmark.circle"))
        return UNNotificationCategory(identifier: identifier, actions: [accept, decline], intentIdentifiers: [], options: [])
    }
}
