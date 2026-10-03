import Foundation
import MetlyCore

/// User-facing strings for CONNECT / INCOMING_REQUEST / CONNECTED (SPEC §2.5.26–27, §7), "Cardy" → `Brand.appName`.
nonisolated enum ConnectCopy {
    static func firstName(of fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    // MARK: CONNECT

    static let title = "Connect"
    static let nearbyTitle = "Looking for People Nearby"
    static let nearbyMessage = "Connect with other \(Brand.appName) users around you. You send your card and get theirs back. To share with someone without the app, use Show My QR."
    static let nearbySectionTitle = "Nearby on \(Brand.appName)"

    static let tapTitle = "Hold Phones Together"
    static let tapMessage = "Hold the top of your iPhone near theirs. \(Brand.appName) needs to be open on both phones."
    static let tapBumpFooter = "Gently tap the tops of your iPhones together."

    static let emptyTitle = "No One Nearby Yet"
    static let emptyMessage = "Ask them to open Connect in \(Brand.appName), or show your QR code instead."
    static let emptyTips = [
        "Both of you need \(Brand.appName) open on the Connect screen.",
        "Stay within a few meters of each other.",
        "Wi‑Fi and Bluetooth should be turned on.",
    ]

    static func noResponse(_ firstName: String) -> String {
        "\(firstName) didn’t respond. Try again or show your QR."
    }

    static func waitingAccessibility(_ firstName: String) -> String {
        "Waiting for \(firstName) to accept"
    }

    static func connectingWith(_ firstName: String) -> String {
        "Connecting with \(firstName)…"
    }

    static func sharingFooter(_ cardName: String) -> String {
        "People you connect with get your \(cardName) card, and you get theirs."
    }

    // MARK: INCOMING_REQUEST

    static let wantsToConnect = "wants to connect with you"

    static func youllShare(_ cardName: String) -> String {
        "You’ll share your \(cardName) card."
    }

    // MARK: CONNECTED

    static let connectedTitle = "You’re Connected"

    static func connectedMessage(_ firstName: String) -> String {
        "You and \(firstName) are connected. Add context while it’s fresh."
    }

    static func sharedCard(_ cardName: String, with firstName: String) -> String {
        "You shared your \(cardName) card with \(firstName)."
    }
}
