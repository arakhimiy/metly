import MetlyData
import SwiftData
import SwiftUI

/// CARD_EDITOR (cover, SPEC §2.5.24) — finds the card, then edits a draft copy of it.
struct CardEditorScreen: View {
    let cardID: UUID
    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    var body: some View {
        if let card = cards.first(where: { $0.id == cardID }) {
            CardEditorForm(card: card, profile: profiles.first)
        } else {
            MissingCardView(title: "Edit Card")
        }
    }
}
