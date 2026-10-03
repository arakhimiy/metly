import MetlyCore
import MetlyData
import SwiftData
import SwiftUI
import UIKit

/// Shared behaviour for MENU_CARD_ACTIONS and "New Card" (used by Home, Profile, Cards).
///
/// ```swift
/// @State private var cardActions = CardActionCoordinator()
/// Menu { CardActionsMenu(hasLink: card.url != nil, isDefault: …, isReadOnly: card.isReadOnly) {
///     cardActions.perform($0, on: card, context: modelContext, router: router, services: services)
/// } }
/// …
/// .cardActionAlerts(cardActions)   // once per screen: delete confirmation + Free card-limit alert
/// ```
@MainActor
@Observable
public final class CardActionCoordinator {
    public var cardPendingDelete: Card?
    public var isConfirmingDelete = false
    public var isShowingLimitAlert = false
    @ObservationIgnored private var pendingContext: (ModelContext, AppRouter, AppServices)?

    public init() {}

    public func perform(_ action: CardAction, on card: Card, context: ModelContext, router: AppRouter, services: AppServices) {
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
            guard let profile = context.currentProfile() else { return }
            profile.defaultCardID = card.id
            profile.markChanged()
            services.sync.requestSync()
            router.showToast("\(card.name) is your default", systemImage: "checkmark.circle")
        case .delete:
            switch CardManagement.planDeletion(of: card.id, cards: Self.summaries(context), defaultID: context.currentProfile()?.defaultCardID) {
            case .blockedLastCard:
                router.showToast("You need at least one card", systemImage: "exclamationmark.circle")
            case .delete:
                cardPendingDelete = card
                pendingContext = (context, router, services)
                isConfirmingDelete = true
            }
        }
    }

    /// "New Card": opens CARD_CREATE, or the Free limit alert (whose CTA opens the paywall).
    public func createCard(context: ModelContext, router: AppRouter, services: AppServices) {
        let count = Self.summaries(context).count
        if CardManagement.canCreateCard(existingCount: count, limits: services.entitlements.limits) {
            router.present(.cardCreate(origin: .home))
        } else {
            pendingContext = (context, router, services)
            isShowingLimitAlert = true
        }
    }

    /// Soft-deletes the card (link stops working once synced) and promotes a new default if needed.
    func confirmDelete() {
        guard let card = cardPendingDelete, let (context, router, services) = pendingContext else { return }
        let profile = context.currentProfile()
        guard case .delete(let newDefaultID) = CardManagement.planDeletion(
            of: card.id, cards: Self.summaries(context), defaultID: profile?.defaultCardID
        ) else { return }
        card.markDeleted()
        if let newDefaultID, let profile {
            profile.defaultCardID = newDefaultID
            profile.markChanged()
        }
        if services.preferences.activeCardID == card.id { services.preferences.activeCardID = nil }
        cardPendingDelete = nil
        services.sync.requestSync()
        router.showToast("Card Deleted", systemImage: "trash")
    }

    func showPaywall() {
        pendingContext?.1.present(.paywall(trigger: .cardLimit))
    }

    private static func summaries(_ context: ModelContext) -> [CardSummary] {
        ((try? context.fetch(Card.live)) ?? []).map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
    }
}

public extension View {
    /// Hosts the delete confirmation and Free card-limit alerts for a `CardActionCoordinator`.
    func cardActionAlerts(_ coordinator: CardActionCoordinator) -> some View {
        modifier(CardActionAlerts(coordinator: coordinator))
    }
}

private struct CardActionAlerts: ViewModifier {
    @Bindable var coordinator: CardActionCoordinator

    func body(content: Content) -> some View {
        content
            .alert("Card Limit Reached", isPresented: $coordinator.isShowingLimitAlert) {
                Button("Not Now", role: .cancel) {}
                Button("See Pro") { coordinator.showPaywall() }
            } message: {
                Text("The Free plan includes 2 cards. Delete one, or upgrade to \(Brand.proName) for unlimited cards.")
            }
            .alert("Delete “\(coordinator.cardPendingDelete?.name ?? "")” Card?", isPresented: $coordinator.isConfirmingDelete) {
                Button("Cancel", role: .cancel) { coordinator.cardPendingDelete = nil }
                Button("Delete", role: .destructive) { coordinator.confirmDelete() }
            } message: {
                Text("Its link and QR code will stop working. People you’ve connected with keep your details.")
            }
    }
}
