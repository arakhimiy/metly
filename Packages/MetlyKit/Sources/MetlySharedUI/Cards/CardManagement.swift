import Foundation
import MetlyCore

/// The bits of a card the management rules need (keeps them testable without SwiftData).
nonisolated public struct CardSummary: Equatable, Sendable {
    public var id: UUID
    public var sortOrder: Int

    public init(id: UUID, sortOrder: Int) {
        self.id = id
        self.sortOrder = sortOrder
    }
}

/// Outcome of asking to delete a card (SPEC §3.6, §2.5.22).
nonisolated public enum CardDeletionPlan: Equatable, Sendable {
    /// The last card can never be deleted ("You need at least one card").
    case blockedLastCard
    /// Soft-delete the card; when it was the default, `newDefaultID` is the card to promote.
    case delete(newDefaultID: UUID?)
}

nonisolated public enum CardManagement {
    /// The stored default when it still exists, otherwise the first card by sort order.
    public static func effectiveDefaultID(cards: [CardSummary], defaultID: UUID?) -> UUID? {
        if let defaultID, cards.contains(where: { $0.id == defaultID }) { return defaultID }
        return cards.min(by: { $0.sortOrder < $1.sortOrder })?.id
    }

    public static func planDeletion(of id: UUID, cards: [CardSummary], defaultID: UUID?) -> CardDeletionPlan {
        let remaining = cards.filter { $0.id != id }.sorted { $0.sortOrder < $1.sortOrder }
        guard let first = remaining.first else { return .blockedLastCard }
        let currentDefault = effectiveDefaultID(cards: cards, defaultID: defaultID)
        return .delete(newDefaultID: currentDefault == id ? first.id : nil)
    }

    /// Free plan: 2 cards (create & duplicate are blocked beyond that). Pro: unlimited.
    public static func canCreateCard(existingCount: Int, limits: PlanLimits) -> Bool {
        limits.allows(count: existingCount, of: \.maxCards)
    }
}
