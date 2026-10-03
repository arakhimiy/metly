import MetlyCore
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var services: AppServices?

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { await Self.services?.push.register(deviceToken: deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator / no aps entitlement — reminders still work via local notifications.
    }
}
