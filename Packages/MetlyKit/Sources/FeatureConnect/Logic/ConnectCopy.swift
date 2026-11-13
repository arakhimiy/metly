import Foundation
import MetlyCore

/// User-facing strings for CONNECT / INCOMING_REQUEST / CONNECTED (SPEC §2.5.26–27, §7), "Cardy" → `Brand.appName`.
nonisolated enum ConnectCopy {
    static func firstName(of fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    // MARK: CONNECT

    static var title: String { String(localized: "Connect", bundle: .appStrings) }
    static var nearbyTitle: String { String(localized: "Looking for People Nearby", bundle: .appStrings) }
    static var nearbyMessage: String { String(localized: "Connect with other \(Brand.appName) users around you. You send your card and get theirs back. To share with someone without the app, use Show My QR.", bundle: .appStrings) }
    static var nearbySectionTitle: String { String(localized: "Nearby on \(Brand.appName)", bundle: .appStrings) }
    static var tapTitle: String { String(localized: "Hold Phones Together", bundle: .appStrings) }
    static var tapMessage: String { String(localized: "Hold the top of your iPhone near theirs. \(Brand.appName) needs to be open on both phones.", bundle: .appStrings) }
    static var tapBumpFooter: String { String(localized: "Gently tap the tops of your iPhones together.", bundle: .appStrings) }
    static var emptyTitle: String { String(localized: "No One Nearby Yet", bundle: .appStrings) }
    static var emptyMessage: String { String(localized: "Ask them to open Connect in \(Brand.appName), or show your QR code instead.", bundle: .appStrings) }
    static var emptyTips: [String] { [
        String(localized: "Both of you need \(Brand.appName) open on the Connect screen.", bundle: .appStrings),
        String(localized: "Stay within a few meters of each other.", bundle: .appStrings),
        String(localized: "Turn on Wi‑Fi and Bluetooth.", bundle: .appStrings),
    ] }

    static func noResponse(_ firstName: String) -> String {
        String(localized: "\(firstName) didn’t respond. Try again or show your QR.", bundle: .appStrings)
    }

    static func waitingAccessibility(_ firstName: String) -> String {
        String(localized: "Waiting for \(firstName) to accept", bundle: .appStrings)
    }

    static func connectingWith(_ firstName: String) -> String {
        String(localized: "Connecting with \(firstName)…", bundle: .appStrings)
    }

    static func sharingFooter(_ cardName: String) -> String {
        String(localized: "People you connect with get your \(cardName) card, and you get theirs.", bundle: .appStrings)
    }

    // MARK: INCOMING_REQUEST

    static var wantsToConnect: String { String(localized: "wants to connect with you", bundle: .appStrings, comment: "Shown on its own line under the person's name") }
    static func youllShare(_ cardName: String) -> String {
        String(localized: "You’ll share your \(cardName) card.", bundle: .appStrings)
    }

    // MARK: CONNECTED

    static var connectedTitle: String { String(localized: "You’re Connected", bundle: .appStrings) }
    static func connectedMessage(_ firstName: String) -> String {
        String(localized: "You and \(firstName) are connected. Add context while it’s fresh.", bundle: .appStrings)
    }

    static func sharedCard(_ cardName: String, with firstName: String) -> String {
        String(localized: "You shared your \(cardName) card with \(firstName).", bundle: .appStrings)
    }
}
