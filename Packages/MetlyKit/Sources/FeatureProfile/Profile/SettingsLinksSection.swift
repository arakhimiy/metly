import MetlyCore
import SwiftUI

/// Notifications · Privacy & Data · Help & Support.
struct SettingsLinksSection: View {
    var body: some View {
        Section {
            NavigationLink(value: PushDestination.settingsNotifications) {
                SettingsRowLabel("Notifications", systemImage: "bell.badge.fill", color: .red)
            }
            NavigationLink(value: PushDestination.settingsPrivacy) {
                SettingsRowLabel("Privacy & Data", systemImage: "hand.raised.fill", color: .blue)
            }
            NavigationLink(value: PushDestination.settingsHelp) {
                SettingsRowLabel("Help & Support", systemImage: "questionmark", color: .green)
            }
        }
    }
}
