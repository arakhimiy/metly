import Foundation
import MetlyCore

/// User-facing strings for CONNECT / INCOMING_REQUEST / CONNECTED (SPEC §2.5.26–27, §7), "Cardy" → `Brand.appName`.
nonisolated enum ConnectCopy {
    static func firstName(of fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    // MARK: CONNECT

    static let title = String(localized: "Connect")
    static let nearbyTitle = String(localized: "Looking for People Nearby")
    static let nearbyMessage = String(localized: "Connect with other \(Brand.appName) users around you. You send your card and get theirs back. To share with someone without the app, use Show My QR.")
    static let nearbySectionTitle = String(localized: "Nearby on \(Brand.appName)")

    static let tapTitle = String(localized: "Hold Phones Together")
    static let tapMessage = String(localized: "Hold the top of your iPhone near theirs. \(Brand.appName) needs to be open on both phones.")
    static let tapBumpFooter = String(localized: "Gently tap the tops of your iPhones together.")

    static let emptyTitle = String(localized: "No One Nearby Yet")
    static let emptyMessage = String(localized: "Ask them to open Connect in \(Brand.appName), or show your QR code instead.")
    static let emptyTips = [
        String(localized: "Both of you need \(Brand.appName) open on the Connect screen."),
        String(localized: "Stay within a few meters of each other."),
        String(localized: "Wi‑Fi and Bluetooth should be turned on."),
    ]

    static func noResponse(_ firstName: String) -> String {
        String(localized: "\(firstName) didn’t respond. Try again or show your QR.")
    }

    static func waitingAccessibility(_ firstName: String) -> String {
        String(localized: "Waiting for \(firstName) to accept")
    }

    static func connectingWith(_ firstName: String) -> String {
        String(localized: "Connecting with \(firstName)…")
    }

    static func sharingFooter(_ cardName: String) -> String {
        String(localized: "People you connect with get your \(cardName) card, and you get theirs.")
    }

    // MARK: INCOMING_REQUEST

    static let wantsToConnect = String(localized: "wants to connect with you", comment: "Shown on its own line under the person's name")

    static func youllShare(_ cardName: String) -> String {
        String(localized: "You’ll share your \(cardName) card.")
    }

    // MARK: CONNECTED

    static let connectedTitle = String(localized: "You’re Connected")

    static func connectedMessage(_ firstName: String) -> String {
        String(localized: "You and \(firstName) are connected. Add context while it’s fresh.")
    }

    static func sharedCard(_ cardName: String, with firstName: String) -> String {
        String(localized: "You shared your \(cardName) card with \(firstName).")
    }
}
