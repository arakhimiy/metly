import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// CARD_EXPORT (cover, SPEC §2.5.25) — finds the card, then shows the export form.
struct CardExportScreen: View {
    let cardID: UUID
    let initialTab: CardExportTab
    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    var body: some View {
        if let card = cards.first(where: { $0.id == cardID }) {
            CardExportForm(card: card, profile: profiles.first, initialTab: initialTab)
        } else {
            MissingCardView(title: String(localized: "Export"))
        }
    }
}
