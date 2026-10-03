import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftData
import SwiftUI

/// "My Cards" (SPEC §2.5.7): paging carousel (tap → QR, long-press → CARD_PREVIEW_MENU), the active
/// card's name / stats / "…" menu, Show QR + Share, draft (publish failed) notice, and New Card.
struct MyCardsSection: View {
    let profile: Profile?
    let cards: [Card]

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var cardActions = CardActionCoordinator()

    var body: some View {
        @Bindable var preferences = services.preferences
        let defaultID = CardManagement.effectiveDefaultID(cards: summaries, defaultID: profile?.defaultCardID)
        let active = activeCard(defaultID: defaultID)

        Section {
            if cards.isEmpty {
                Button("Create Your First Card", systemImage: "plus.rectangle.on.rectangle", action: createCard)
                    .frame(minHeight: 44)
            } else {
                CardCarousel(cards: cards, profile: profile, defaultCardID: defaultID,
                             selection: $preferences.activeCardID, onShowQR: showQR, onAction: perform)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        } header: {
            HomeSectionHeader(Text("My Cards")) {
                Button("New Card", systemImage: "plus", action: createCard)
                    .labelStyle(.titleAndIcon)
            }
        }
        .headerProminence(.increased)
        .listSectionSpacing(.compact)
        .cardActionAlerts(cardActions)
        .task(id: cards.map(\.id)) { restoreActiveCard(defaultID: defaultID) }

        // The active card's panel gets its own grouped section (rounded on every corner).
        if let active {
            Section {
                ActiveCardPanel(card: active, isDefault: active.id == defaultID,
                                onAction: { perform($0, on: active) },
                                onShowQR: { showQR(active) },
                                onShare: { share(active) })
                if active.publishState == .draft {
                    DraftCardNotice(cardName: active.name)
                }
            }
        }
    }

    private var summaries: [CardSummary] {
        cards.map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
    }

    /// The carousel's card (remembered across launches), else the default card.
    private func activeCard(defaultID: UUID?) -> Card? {
        let id = services.preferences.activeCardID ?? defaultID
        return cards.first { $0.id == id } ?? cards.first { $0.id == defaultID } ?? cards.first
    }

    /// Points the carousel at a live card (first launch, or the remembered card was deleted).
    private func restoreActiveCard(defaultID: UUID?) {
        let preferences = services.preferences
        guard !cards.contains(where: { $0.id == preferences.activeCardID }) else { return }
        preferences.activeCardID = defaultID ?? cards.first?.id
    }

    private func showQR(_ card: Card) {
        router.present(.qr(cardID: card.id))
    }

    private func share(_ card: Card) {
        router.present(.share(cardID: card.id))
    }

    private func perform(_ action: CardAction, on card: Card) {
        cardActions.perform(action, on: card, context: modelContext, router: router, services: services)
    }

    private func createCard() {
        cardActions.createCard(context: modelContext, router: router, services: services)
    }
}
