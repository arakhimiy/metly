import MetlyCore
import MetlyData
import SwiftUI

/// "Cards": every live card with its MENU_CARD_ACTIONS, plus "New Card" (Free limit → paywall).
struct CardsSection: View {
    let profile: Profile
    let cards: [Card]
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var cardToDelete: Card?
    @State private var isConfirmingDelete = false
    @State private var isShowingLimitAlert = false

    var body: some View {
        let defaultID = CardManagement.effectiveDefaultID(cards: summaries, defaultID: profile.defaultCardID)

        Section {
            ForEach(cards) { card in
                CardRow(
                    card: card,
                    faceContent: card.faceContent(profile: profile, audience: .connections),
                    isDefault: card.id == defaultID
                ) { action in
                    perform(action, on: card)
                }
            }

            Button("New Card", systemImage: "plus.circle.fill", action: createCard)
                .frame(minHeight: 44)
                .alert("Card Limit Reached", isPresented: $isShowingLimitAlert) {
                    Button("Not Now", role: .cancel) {}
                    Button("See Pro", action: showPaywall)
                } message: {
                    Text("The Free plan includes 2 cards. Delete one, or upgrade to \(Brand.proName) for unlimited cards.")
                }
                .alert(deleteAlertTitle, isPresented: $isConfirmingDelete, presenting: cardToDelete) { card in
                    Button("Cancel", role: .cancel) {}
                    Button("Delete", role: .destructive) { delete(card) }
                } message: { _ in
                    Text("Its link and QR code will stop working. People you’ve connected with keep your details.")
                }
        } header: {
            Text("Cards")
        } footer: {
            Text("Your default card is used for Connect, events and widgets.")
        }
    }

    private var summaries: [CardSummary] {
        cards.map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
    }

    private var deleteAlertTitle: String {
        "Delete “\(cardToDelete?.name ?? "")” Card?"
    }

    // MARK: Actions

    private func createCard() {
        if CardManagement.canCreateCard(existingCount: cards.count, limits: services.entitlements.limits) {
            router.present(.cardCreate(origin: .home))
        } else {
            isShowingLimitAlert = true
        }
    }

    private func showPaywall() {
        router.present(.paywall(trigger: .cardLimit))
    }

    private func perform(_ action: CardAction, on card: Card) {
        switch action {
        case .copyLink:
            guard let url = card.url else { return }
            UIPasteboard.general.url = url
            router.showToast("Link Copied", systemImage: "link")
        case .share:
            router.present(.share(cardID: card.id))
        case .showQR:
            router.present(.qr(cardID: card.id))
        case .connect:
            router.present(.connect(cardID: card.id))
        case .edit:
            router.present(.cardEditor(cardID: card.id))
        case .settings:
            router.push(.cardSettings(id: card.id))
        case .export:
            router.present(.cardExport(cardID: card.id, tab: .image))
        case .setDefault:
            setDefault(card)
        case .delete:
            requestDeletion(of: card)
        }
    }

    private func setDefault(_ card: Card) {
        profile.defaultCardID = card.id
        profile.markChanged()
        services.sync.requestSync()
        router.showToast("\(card.name) is your default", systemImage: "checkmark.circle")
    }

    private func requestDeletion(of card: Card) {
        switch CardManagement.planDeletion(of: card.id, cards: summaries, defaultID: profile.defaultCardID) {
        case .blockedLastCard:
            router.showToast("You need at least one card", systemImage: "exclamationmark.circle")
        case .delete:
            cardToDelete = card
            isConfirmingDelete = true
        }
    }

    /// Soft-deletes the card (its link stops working once synced) and promotes a new default if needed.
    private func delete(_ card: Card) {
        guard case .delete(let newDefaultID) = CardManagement.planDeletion(
            of: card.id, cards: summaries, defaultID: profile.defaultCardID
        ) else { return }

        card.markDeleted()
        if let newDefaultID {
            profile.defaultCardID = newDefaultID
            profile.markChanged()
        }
        if services.preferences.activeCardID == card.id {
            services.preferences.activeCardID = nil
        }
        cardToDelete = nil
        services.sync.requestSync()
        router.showToast("Card Deleted", systemImage: "trash")
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
