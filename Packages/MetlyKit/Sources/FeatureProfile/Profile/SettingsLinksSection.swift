import MetlyCore
import SwiftUI

/// Appearance (MENU_APPEARANCE: System / Light / Dark, applied by the app root) ·
/// Language · Notifications · Privacy & Data. Rate, support and legal links: `SupportSection`.
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

            // Switches the whole app at once (the root re-renders in the new language).
            Picker(selection: languageBinding) {
                ForEach(AppLanguage.allCases) { language in
                    Text(verbatim: language.nativeName).tag(language)
                }
            } label: {
                SettingsRowLabel("Language", systemImage: "globe", color: .blue)
            }
            .pickerStyle(.menu)

            NavigationLink(value: PushDestination.settingsNotifications) {
                SettingsRowLabel("Notifications", systemImage: "bell.badge.fill", color: .red)
            }
            NavigationLink(value: PushDestination.settingsPrivacy) {
                SettingsRowLabel("Privacy & Data", systemImage: "hand.raised.fill", color: .blue)
            }
        }
    }

    /// Never nil here: a signed-in person passed the language screen, and older installs show the
    /// language the app runs in.
    private var languageBinding: Binding<AppLanguage> {
        Binding(get: { services.preferences.language ?? AppLanguage.current },
                set: { services.preferences.language = $0 })
    }
}
