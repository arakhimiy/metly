import MetlyCore
import SwiftUI

/// MENU_APPEARANCE — System / Light / Dark, stored on the device; the app root applies it.
struct AppearanceSection: View {
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
        }
    }
}
