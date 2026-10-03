import MetlyCore

/// The App Shortcuts phrases shown in WIDGETS_GALLERY.
///
/// Keep in sync with `MetlyAppShortcuts` in `Metly/AppIntents/` (the provider must live in the app
/// target, so the gallery can't read it directly).
public struct WidgetShortcutPhrase: Identifiable, Hashable, Sendable {
    public let text: String
    public let detail: String
    public let systemImage: String

    public var id: String { text }

    public static var all: [WidgetShortcutPhrase] {
        [
            WidgetShortcutPhrase(text: String(localized: "Show my \(Brand.appName) QR"),
                                 detail: String(localized: "Opens your QR code full screen."), systemImage: "qrcode"),
            WidgetShortcutPhrase(text: String(localized: "Show my card in \(Brand.appName)"),
                                 detail: String(localized: "Same, with the card you share right now."), systemImage: "person.text.rectangle"),
            WidgetShortcutPhrase(text: String(localized: "Show my follow-ups in \(Brand.appName)"),
                                 detail: String(localized: "Opens your reminders."), systemImage: "bell"),
            WidgetShortcutPhrase(text: String(localized: "Start an event in \(Brand.appName)"),
                                 detail: String(localized: "Tags everyone you meet with the event."), systemImage: "flag"),
        ]
    }
}
