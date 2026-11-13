import Foundation
import MetlyCore

/// Count-dependent copy for SETTINGS_DELETE_ACCOUNT and other account screens.
nonisolated enum AccountCopy {
    static func deleteAccountMessage(cardCount: Int, peopleCount: Int) -> String {
        let cards = cardCount == 1 ? String(localized: "1 card", bundle: .appStrings) : String(localized: "\(cardCount) cards", bundle: .appStrings)
        let people = peopleCount == 1 ? String(localized: "1 person", bundle: .appStrings) : String(localized: "\(peopleCount) people", bundle: .appStrings)
        let cardsWithLinks = cardCount == 1 ? String(localized: "\(cards) with its link and QR code", bundle: .appStrings) : String(localized: "\(cards) with their links and QR codes", bundle: .appStrings)
        return String(localized: "This permanently deletes your profile, \(cardsWithLinks), and your notes on \(people). Printed QR codes will show an inactive page.", bundle: .appStrings)
    }

    static var signOutMessage: String { String(localized: "You can sign back in with Apple or Google.", bundle: .appStrings) }
    static var afterCancelMessage: String { String(localized: "If you cancel, you keep Pro until the end of this billing period. Cards beyond two become read-only after that.", bundle: .appStrings) }
    static var billingFooter: String { String(localized: "Subscriptions are billed through your Apple ID. Cancel at least 24 hours before renewal.", bundle: .appStrings) }
}
