import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// CARD_SETTINGS (push, title "{Name} Card", SPEC §2.5.22). Pops itself once the card is deleted.
struct CardSettingsScreen: View {
    let cardID: UUID
    @Environment(AppRouter.self) private var router
    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    var body: some View {
        Group {
            if let card = cards.first(where: { $0.id == cardID }) {
                CardSettingsForm(card: card, cards: cards, profile: profiles.first)
            } else {
                ContentUnavailableView("Card Deleted", systemImage: "rectangle.on.rectangle.slash",
                                       description: Text("This card no longer exists."))
            }
        }
        .onChange(of: cardExists) { existed, exists in
            if existed, !exists { popIfOnTop() }
        }
    }

    private var cardExists: Bool { cards.contains { $0.id == cardID } }

    /// "Delete Card" → back to the previous screen (only if this screen is still on top).
    private func popIfOnTop() {
        if router.paths[router.selectedTab]?.last == .cardSettings(id: cardID) {
            router.pop()
        }
    }
}
