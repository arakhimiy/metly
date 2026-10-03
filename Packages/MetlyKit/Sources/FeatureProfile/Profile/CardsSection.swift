import MetlyCore
import MetlyData
import SwiftUI
import MetlySharedUI

/// "Cards": every live card with its MENU_CARD_ACTIONS, plus "New Card" (Free limit → paywall).
struct CardsSection: View {
    let profile: Profile
    let cards: [Card]
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var cardActions = CardActionCoordinator()

    var body: some View {
        let defaultID = CardManagement.effectiveDefaultID(cards: summaries, defaultID: profile.defaultCardID)

        Section {
            ForEach(cards) { card in
                CardRow(
                    card: card,
                    faceContent: card.faceContent(profile: profile, audience: .connections),
                    isDefault: card.id == defaultID
                ) { action in
                    cardActions.perform(action, on: card, context: modelContext, router: router, services: services)
                }
            }

            Button("New Card", systemImage: "plus.circle.fill") {
                cardActions.createCard(context: modelContext, router: router, services: services)
            }
            .frame(minHeight: 44)
            .cardActionAlerts(cardActions)
        } header: {
            Text("Cards")
        } footer: {
            Text("Your default card is used for Connect, events and widgets.")
        }
    }

    private var summaries: [CardSummary] {
        cards.map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
    }
}

#Preview("Cards · menu") {
    NavigationStack {
        Form {
            CardsPreviewHost()
        }
    }
    .metlyPreview(.full)
}

#Preview("Cards · single card, Pro") {
    NavigationStack {
        Form {
            CardsPreviewHost()
        }
    }
    .metlyPreview(.empty, plan: .pro)
}

/// Loads profile + cards from the preview store for the section previews.
private struct CardsPreviewHost: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        if let profile = modelContext.currentProfile() {
            CardsSection(profile: profile, cards: (try? modelContext.fetch(Card.live)) ?? [])
        }
    }
}
