import MetlyCore
import SwiftUI
import UIKit

/// Tells the owner reminders won't arrive: iOS notifications denied, or follow-up reminders turned off.
struct RemindersOffSection: View {
    enum Notice {
        case systemDenied
        case turnedOff
    }

    let notice: Notice

    @Environment(AppRouter.self) private var router
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "bell.slash")
                    .foregroundStyle(.orange)
            }
            .accessibilityElement(children: .combine)

            switch notice {
            case .systemDenied:
                Button("Open Settings", action: openSettings)
            case .turnedOff:
                Button("Notification Settings", action: openNotificationSettings)
            }
        }
    }

    private var title: String {
        switch notice {
        case .systemDenied: String(localized: "Notifications Are Off")
        case .turnedOff: String(localized: "Follow-up Reminders Are Off")
        }
    }

    private var message: String {
        switch notice {
        case .systemDenied:
            String(localized: "Turn on notifications for \(Brand.appName) in iOS Settings so you’re reminded on time.")
        case .turnedOff:
            String(localized: "You won’t be notified when a follow-up is due.")
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
    }

    private func openNotificationSettings() {
        router.push(.settingsNotifications)
    }
}
