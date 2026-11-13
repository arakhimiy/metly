import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// SETTINGS_PRIVACY (SPEC §2.5.18).
struct PrivacySettingsScreen: View {
    var body: some View {
        ProfileReader { profile in
            PrivacySettingsForm(profile: profile)
        }
        .navigationTitle("Privacy & Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacySettingsForm: View {
    let profile: Profile
    @Environment(AppServices.self) private var services
    @Query(filter: #Predicate<Connection> { $0.isBlocked && $0.deletedAt == nil }) private var blockedPeople: [Connection]

    var body: some View {
        let editor = profile.editor
        Form {
            Section {
                Toggle(isOn: editor.binding(\.privacySettings.findByEmail)) {
                    Text("Find Me by Email")
                    Text("People with your email can send a connect request")
                }
                Toggle(isOn: editor.binding(\.privacySettings.showInNearby)) {
                    Text("Show in Nearby")
                    Text("Appear in Connect for people around you")
                }
            } header: {
                Text("Discovery")
            } footer: {
                Text("With both off, only people you share your link or QR code with can reach you.")
            }

            Section {
                Toggle(isOn: editor.binding(\.privacySettings.shareAnalytics)) {
                    Text("Share Usage Analytics")
                    Text("Anonymous usage that helps improve \(Brand.appName)")
                }
            } footer: {
                Text("Analytics never include your contacts, notes or the people you meet.")
            }

            Section {
                DataExportButton()
                NavigationLink(value: PushDestination.settingsBlockedPeople) {
                    LabeledContent("Blocked People") {
                        Text(blockedPeople.count, format: .number)
                    }
                }
            } header: {
                Text("Your Data")
            } footer: {
                Text("\(Brand.appName) never sells your data. Notes you write are only visible to you.")
            }

            Section {
                NavigationLink(value: PushDestination.settingsDeleteAccount) {
                    Text("Delete Account")
                        .foregroundStyle(.red)
                }
            }
        }
        .onDisappear {
            services.sync.requestSync()
        }
    }
}

#Preview("Privacy & Data") {
    NavigationStack { PrivacySettingsScreen() }
        .metlyPreview(.full)
}

#Preview("Privacy & Data · discovery off") {
    NavigationStack { PrivacySettingsScreen() }
        .profilePreview {
            $0.privacySettings.findByEmail = false
            $0.privacySettings.showInNearby = false
        }
}
