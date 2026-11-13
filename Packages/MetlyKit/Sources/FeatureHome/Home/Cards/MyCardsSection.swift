import MetlyCore
import MetlyData
import MetlyDesign
import MetlySharedUI
import SwiftData
import SwiftUI

/// The cards at the top of Home (SPEC §2.5.7): paging carousel (long-press → CARD_PREVIEW_MENU,
/// tap → CARD_SETTINGS) and the draft (publish failed) notice. No header or panel: the cards speak for
/// themselves, Show QR / Share sit in the toolbar (`HomeScreen`), New Card lives in Profile.
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
                EmptyStateView(.cards, title: "Make Your First Card",
                               message: "Share it as a QR code, a link or in Apple Wallet.", style: .inline) {
                    Button("Create Your First Card", systemImage: "plus", action: createCard)
                        .subtleButtonStyle()
                }
            } else {
                CardCarousel(cards: cards, profile: profile, defaultCardID: defaultID,
                             selection: $preferences.activeCardID, onOpen: { perform(.settings, on: $0) }, onAction: perform)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
            }
        }
        .listSectionSpacing(.compact)
        .cardActionAlerts(cardActions)
        .task(id: cards.map(\.id)) { restoreActiveCard(defaultID: defaultID) }

        // Publish failed: say so under the carousel, in its own grouped section.
        if let active, active.publishState == .draft {
            Section {
                DraftCardNotice(cardName: active.name)
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

    private func perform(_ action: CardAction, on card: Card) {
        cardActions.perform(action, on: card, context: modelContext, router: router, services: services)
    }

    private func createCard() {
        cardActions.createCard(context: modelContext, router: router, services: services)
    }
}
