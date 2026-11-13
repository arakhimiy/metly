import MetlyCore
import MetlyData
import SwiftUI
import UserNotifications

/// SETTINGS_NOTIFICATIONS (SPEC §2.5.17).
struct NotificationSettingsScreen: View {
    /// Previews inject a permission state instead of asking iOS.
    var previewPermission: NotificationPermission?

    var body: some View {
        ProfileReader { profile in
            NotificationSettingsForm(profile: profile, previewPermission: previewPermission)
        }
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct NotificationSettingsForm: View {
    let profile: Profile
    let previewPermission: NotificationPermission?
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: NotificationPermission = .unknown

    var body: some View {
        let editor = profile.editor

        Form {
            NotificationPermissionSection(permission: permission, requestPermission: requestPermission, openSettings: openSystemSettings)

            Section("Reminders") {
                Toggle(isOn: editor.binding(\.notificationPrefs.followUpReminders)) {
                    Text("Follow-up Reminders")
                    Text("On the day you picked, with the reason")
                }
                Toggle(isOn: editor.binding(\.notificationPrefs.eventSummary)) {
                    Text("Event Summary")
                    Text("When an event ends: who you met and what’s left")
                }
            }

            Section {
                Toggle(isOn: editor.binding(\.notificationPrefs.connectRequests)) {
                    Text("Connect Requests")
                    Text("When someone nearby wants your card")
                }
                Toggle(isOn: editor.binding(\.notificationPrefs.cardSaved)) {
                    Text("Card Saved")
                    Text("When someone adds you to Contacts")
                }
                Toggle(isOn: editor.binding(\.notificationPrefs.weeklySummary)) {
                    Text("Weekly Summary")
                    Text("New connections and card views")
                }
            } header: {
                Text("Activity")
            } footer: {
                Text("Summaries arrive quietly, without sound.")
            }

            Section("From \(Brand.appName)") {
                Toggle("Product News", isOn: editor.binding(\.notificationPrefs.productNews))
            }
        }
        .task(id: scenePhase) {
            // Re-check when coming back from iOS Settings.
            if scenePhase == .active { await refreshPermission() }
        }
        .onDisappear {
            services.sync.requestSync()
        }
    }

    // MARK: Permission

    private func refreshPermission() async {
        permission = if let previewPermission { previewPermission } else { await NotificationPermission.current() }
    }

    private func requestPermission() {
        Task {
            let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])) ?? false
            if granted { UIApplication.shared.registerForRemoteNotifications() }
            await refreshPermission()
        }
    }

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openNotificationSettingsURLString) {
            openURL(url)
        }
    }
}

#Preview("Notifications · allowed") {
    NavigationStack { NotificationSettingsScreen(previewPermission: .authorized) }
        .metlyPreview(.full)
}

#Preview("Notifications · denied") {
    NavigationStack { NotificationSettingsScreen(previewPermission: .denied) }
        .metlyPreview(.full)
}

#Preview("Notifications · not asked") {
    NavigationStack { NotificationSettingsScreen(previewPermission: .notDetermined) }
        .metlyPreview(.full)
}
