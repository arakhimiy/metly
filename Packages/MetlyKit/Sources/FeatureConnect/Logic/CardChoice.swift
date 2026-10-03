import Foundation
import MetlyData
import SwiftData

/// Which card CONNECT sends (SPEC §9 Q47/Q48):
/// 1. the card the caller asked for (QR "Connect Nearby", a card's menu), if it still exists;
/// 2. otherwise the card to share right now — the active event's card, else the default card
///    (`ModelContext.cardToShare()`);
/// 3. otherwise the first live card.
/// The user can change it with the card chooser.
nonisolated enum CardChoice {
    static func initialCardID(requested: UUID?, cardToShare: UUID?, liveCardIDs: [UUID]) -> UUID? {
        if let requested, liveCardIDs.contains(requested) { return requested }
        if let cardToShare, liveCardIDs.contains(cardToShare) { return cardToShare }
        return liveCardIDs.first
    }

    /// Keeps the current choice while it exists; falls back to `initialCardID` (e.g. the chosen card was deleted).
    static func validated(_ current: UUID?, requested: UUID?, cardToShare: UUID?, liveCardIDs: [UUID]) -> UUID? {
        if let current, liveCardIDs.contains(current) { return current }
        return initialCardID(requested: requested, cardToShare: cardToShare, liveCardIDs: liveCardIDs)
    }
}

extension CardChoice {
    /// `initialCardID` read from the store.
    @MainActor
    static func initialCardID(requested: UUID?, in modelContext: ModelContext) -> UUID? {
        let live = ((try? modelContext.fetch(Card.live)) ?? []).map(\.id)
        return initialCardID(requested: requested, cardToShare: modelContext.cardToShare()?.id, liveCardIDs: live)
    }
}
