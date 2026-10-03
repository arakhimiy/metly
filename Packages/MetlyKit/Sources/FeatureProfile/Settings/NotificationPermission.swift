import UserNotifications

/// iOS notification authorization, simplified for SETTINGS_NOTIFICATIONS.
enum NotificationPermission: Equatable {
    case unknown, notDetermined, denied, authorized

    init(_ status: UNAuthorizationStatus) {
        switch status {
        case .notDetermined: self = .notDetermined
        case .denied: self = .denied
        case .authorized, .provisional, .ephemeral: self = .authorized
        @unknown default: self = .unknown
        }
    }

    static func current() async -> NotificationPermission {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return NotificationPermission(settings.authorizationStatus)
    }
}
