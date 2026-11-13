import Foundation
import MetlyCore

/// `nameshake://` links opened by widgets, the Control Center control and App Shortcuts.
/// The app's `DeepLinkHandler` resolves them (hosts `qr`, `followups`, `reminder`, …).
nonisolated public enum WidgetDeepLink {
    /// QR_FULLSCREEN for `cardID`, or for the card to share at tap time when nil.
    public static func qr(cardID: UUID? = nil) -> URL {
        url(host: "qr", path: cardID?.uuidString)
    }

    /// FOLLOWUPS on the Home tab.
    public static var followUps: URL { url(host: "followups") }

    /// REMINDER_EDIT for one follow-up.
    public static func reminder(_ followUpID: UUID) -> URL {
        url(host: "reminder", path: followUpID.uuidString)
    }

    /// START_EVENT (needs the `event` host in `DeepLinkHandler`, see the Widgets & Intents report).
    public static var startEvent: URL { url(host: "event", path: "start") }

    /// Just opens the app (signed-out / empty widgets).
    public static var app: URL { url(host: "home") }

    private static func url(host: String, path: String? = nil) -> URL {
        var components = URLComponents()
        components.scheme = Brand.urlScheme
        components.host = host
        if let path { components.path = "/" + path }
        return components.url ?? URL(string: "\(Brand.urlScheme)://\(host)")!
    }
}

/// Widget `kind` identifiers (stable — renaming one removes it from people's Home Screens).
nonisolated public enum WidgetKind {
    public static let myQR = "app.nameshake.ios.widget.qr"
    public static let card = "app.nameshake.ios.widget.card"
    public static let followUps = "app.nameshake.ios.widget.followups"
    public static let lockScreenQR = "app.nameshake.ios.widget.lockqr"
    public static let showQRControl = "app.nameshake.ios.control.showqr"

    public static let all = [myQR, card, followUps, lockScreenQR]
}
