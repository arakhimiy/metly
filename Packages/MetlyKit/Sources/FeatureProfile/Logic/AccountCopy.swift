import Foundation
import MetlyCore

/// Count-dependent copy for SETTINGS_DELETE_ACCOUNT and other account screens.
nonisolated enum AccountCopy {
    static func deleteAccountMessage(cardCount: Int, peopleCount: Int) -> String {
        let cards = cardCount == 1 ? "1 card" : "\(cardCount) cards"
        let people = peopleCount == 1 ? "1 person" : "\(peopleCount) people"
        let cardsWithLinks = cardCount == 1 ? "\(cards) with its link and QR code" : "\(cards) with their links and QR codes"
        return "This permanently deletes your profile, \(cardsWithLinks), and your notes on \(people). Printed QR codes will show an inactive page."
    }

    static let signOutMessage = "You can sign back in with Apple or Google."
    static let afterCancelMessage = "If you cancel, you keep Pro until the end of this billing period. Cards beyond two become read-only after that."
    static let billingFooter = "Subscriptions are billed through your Apple ID. Cancel at least 24 hours before renewal."
}
