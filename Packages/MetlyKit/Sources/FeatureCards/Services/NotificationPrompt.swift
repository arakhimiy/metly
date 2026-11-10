import UIKit
import UserNotifications

/// Asks for notification permission once the first card is ready — the moment its value is clear
/// (someone saves the card or sends their contact) — instead of during setup. Only ever asks once.
enum NotificationPrompt {
    static func askIfNeeded() async {
        // Outside an app bundle (previews, unit tests) the notification center isn't available.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        let center = UNUserNotificationCenter.current()
        guard await center.notificationSettings().authorizationStatus == .notDetermined else { return }
        if (try? await center.requestAuthorization(options: [.alert, .badge, .sound])) == true {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
