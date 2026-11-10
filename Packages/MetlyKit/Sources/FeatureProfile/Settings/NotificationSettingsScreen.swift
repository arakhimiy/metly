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
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase
    @State private var permission: NotificationPermission = .unknown
    @State private var isShowingTelegramAlert = false

    var body: some View {
        let editor = profile.editor
        let prefs = profile.notificationPrefs

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

            if TelegramLinking.isAvailable || prefs.telegramLinked {
                Section {
                    Picker("Deliver Reminders Via", selection: editor.deliveryBinding { [alert = $isShowingTelegramAlert] in
                        alert.wrappedValue = true
                    }) {
                        Text("Push Notifications")
                            .tag(ReminderDelivery.push)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Telegram Bot")
                            Text(prefs.telegramLinked ? "Connected · \(TelegramLinking.botHandle)" : "Not connected")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .tag(ReminderDelivery.telegramBot)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()

                    if prefs.telegramLinked {
                        Button("Disconnect Telegram", role: .destructive, action: disconnectTelegram)
                    } else {
                        Button("Connect Telegram", systemImage: "paperplane", action: showTelegramAlert)
                    }
                } header: {
                    Text("Deliver Reminders Via")
                } footer: {
                    Text("The bot sends each reminder with a one-tap link to the chat.")
                }
                .alert("Connect Telegram Bot", isPresented: $isShowingTelegramAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Open Telegram", action: connectTelegram)
                } message: {
                    Text("Open \(TelegramLinking.botHandle) and tap Start. Reminders arrive in the chat with a link to reply.")
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

    // MARK: Telegram

    private func showTelegramAlert() {
        isShowingTelegramAlert = true
    }

    private func connectTelegram() {
        guard let url = TelegramLinking.startURL(token: TelegramLinking.placeholderToken()) else { return }
        let editor = profile.editor
        let router = router
        let services = services
        openURL(url) { accepted in
            guard accepted else {
                router.showToast(String(localized: "Couldn’t Open Telegram"), systemImage: "exclamationmark.triangle")
                return
            }
            // TODO(backend): wait for the bot to confirm the link (synced `telegramLinked`) instead of assuming it.
            editor.updateNotificationPrefs {
                $0.telegramLinked = true
                $0.delivery = .telegramBot
            }
            services.sync.requestSync()
            router.showToast(String(localized: "Telegram Connected"), systemImage: "paperplane.fill")
        }
    }

    private func disconnectTelegram() {
        // TODO(backend): also unlink the chat server-side.
        profile.editor.updateNotificationPrefs {
            $0.telegramLinked = false
            $0.delivery = .push
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

#Preview("Notifications · not asked, Telegram linked") {
    NavigationStack { NotificationSettingsScreen(previewPermission: .notDetermined) }
        .profilePreview {
            $0.notificationPrefs.telegramLinked = true
            $0.notificationPrefs.delivery = .telegramBot
        }
}
