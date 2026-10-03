import MetlyCore
import SwiftUI

/// Appearance (MENU_APPEARANCE: System / Light / Dark, applied by the app root) ·
/// Notifications · Privacy & Data · Help & Support.
struct SettingsLinksSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        @Bindable var preferences = services.preferences
        Section {
            Picker(selection: $preferences.appearance) {
                ForEach(AppAppearance.allCases) { appearance in
                    Text(appearance.title).tag(appearance)
                }
            } label: {
                SettingsRowLabel("Appearance", systemImage: "circle.lefthalf.filled", color: .indigo)
            }
            .pickerStyle(.menu)
            .sensoryFeedback(.selection, trigger: preferences.appearance)

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
