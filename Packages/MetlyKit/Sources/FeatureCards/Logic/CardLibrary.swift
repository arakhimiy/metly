import Foundation
import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftData

/// Card mutations used by CARD_CREATE and CARD_SETTINGS. Every write marks the touched records
/// dirty for sync; the sync engine assigns the slug / publishes (cards start as drafts).
@MainActor
enum CardLibrary {
    static func liveCards(in context: ModelContext) -> [Card] {
        (try? context.fetch(Card.live)) ?? []
    }

    static func summaries(_ cards: [Card]) -> [CardSummary] {
        cards.map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
    }

    /// Inserts a new card at the end of the Home order. The very first card becomes the default.
    @discardableResult
    static func create(name: String, design: CardDesign, in context: ModelContext) -> Card {
        let existing = liveCards(in: context)
        let card = Card(name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        sortOrder: CardOrdering.nextSortOrder(after: summaries(existing)),
                        design: design)
        context.insert(card)
        if existing.isEmpty, let profile = context.currentProfile() {
            profile.defaultCardID = card.id
            profile.markChanged()
        }
        return card
    }

    /// "{name} Copy" with the same design, placed right after the original. The server gives it a new slug.
    @discardableResult
    static func duplicate(_ source: Card, in context: ModelContext) -> Card {
        let existing = liveCards(in: context)
        let copy = Card(name: CardNaming.copyName(for: source.name, existing: existing.map(\.name)),
                        sortOrder: source.sortOrder + 1, design: source.design)
        context.insert(copy)
        let order = CardOrdering.inserting(copy.id, after: source.id,
                                           in: CardOrdering.orderedIDs(summaries(existing)))
        applyOrder(order, to: existing + [copy])
        return copy
    }

    /// Writes `order` into `sortOrder`, touching only cards whose position changed.
    static func applyOrder(_ order: [UUID], to cards: [Card]) {
        let changes = CardOrdering.changes(from: summaries(cards), to: order)
        for card in cards {
            guard let sortOrder = changes[card.id] else { continue }
            card.sortOrder = sortOrder
            card.markChanged()
        }
    }

    /// Card Settings "Name". Returns whether the name changed. Read-only cards (beyond the Free
    /// limit after a downgrade) can't be edited, and that includes their name.
    @discardableResult
    static func rename(_ card: Card, to name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != card.name, !card.isDeleted, !card.isReadOnly else { return false }
        card.name = trimmed
        card.markChanged()
        return true
    }

    /// Makes `card` the default (SPEC: "Used for Connect, events and widgets").
    static func setDefault(_ card: Card, profile: Profile) {
        guard profile.defaultCardID != card.id else { return }
        profile.defaultCardID = card.id
        profile.markChanged()
    }

    static func isDefault(_ card: Card, among cards: [Card], profile: Profile?) -> Bool {
        CardManagement.effectiveDefaultID(cards: summaries(cards), defaultID: profile?.defaultCardID) == card.id
    }
}
