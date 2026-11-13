import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// SETTINGS (Profile › ⚙️): Nameshake Pro · Sharing (Pause All Links, Preview Public Page) ·
/// Appearance, Notifications, Privacy & Data, Help & Support · Sign Out.
struct SettingsScreen: View {
    @Query(Card.live) private var cards: [Card]

    var body: some View {
        ProfileReader { profile in
            Form {
                ProPlanSection()
                SharingSection(profile: profile, cards: cards)
                SettingsLinksSection()
                SupportSection()
                SignOutSection()
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Settings") {
    NavigationStack { SettingsScreen() }
        .metlyPreview(.full)
}
