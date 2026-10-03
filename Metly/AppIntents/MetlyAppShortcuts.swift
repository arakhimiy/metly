import AppIntents

/// App Shortcuts: available in Siri, Spotlight and Shortcuts without setup.
/// The phrases are listed in WIDGETS_GALLERY (`WidgetShortcutPhrase.all`) — keep both in sync.
nonisolated struct MetlyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ShowMyQRIntent(),
            phrases: [
                "Show my \(.applicationName) QR",
                "Show my card in \(.applicationName)",
                "Show my QR code in \(.applicationName)",
                "Open my \(.applicationName) QR code",
            ],
            shortTitle: "Show My QR",
            systemImageName: "qrcode"
        )
        AppShortcut(
            intent: OpenFollowUpsIntent(),
            phrases: [
                "Show my follow-ups in \(.applicationName)",
                "Open \(.applicationName) follow-ups",
                "Who should I follow up with in \(.applicationName)",
            ],
            shortTitle: "Follow-ups",
            systemImageName: "bell"
        )
        AppShortcut(
            intent: StartEventIntent(),
            phrases: [
                "Start an event in \(.applicationName)",
                "Start event mode in \(.applicationName)",
            ],
            shortTitle: "Start Event",
            systemImageName: "flag"
        )
    }

    static let shortcutTileColor: ShortcutTileColor = .teal
}
