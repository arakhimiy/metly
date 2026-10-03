import Foundation
import MetlySharedUI

/// Home order of cards (`Card.sortOrder`, SPEC §2.5.22 "Order"). Pure, so the math is unit-tested.
///
/// Orders are always renormalised to 0…n-1 and only cards whose number actually changed are
/// reported, so a reorder marks the minimum number of records dirty for sync.
nonisolated enum CardOrdering {
    /// IDs sorted by `sortOrder` (ties keep their given order).
    static func orderedIDs(_ cards: [CardSummary]) -> [UUID] {
        cards.enumerated()
            .sorted { ($0.element.sortOrder, $0.offset) < ($1.element.sortOrder, $1.offset) }
            .map(\.element.id)
    }

    /// `List.onMove` semantics: moves the items at `offsets` so they land before `destination`.
    static func moving(_ ids: [UUID], fromOffsets offsets: IndexSet, toOffset destination: Int) -> [UUID] {
        let moving = offsets.sorted().filter { ids.indices.contains($0) }
        let movingIDs = moving.map { ids[$0] }
        let insertAt = destination - moving.count(where: { $0 < destination })
        var remaining = ids.enumerated().filter { !moving.contains($0.offset) }.map(\.element)
        remaining.insert(contentsOf: movingIDs, at: min(max(insertAt, 0), remaining.count))
        return remaining
    }

    /// Moves one card a step up (-1) or down (+1); nil at the ends.
    static func moving(_ id: UUID, by step: Int, in ids: [UUID]) -> [UUID]? {
        guard let index = ids.firstIndex(of: id) else { return nil }
        let target = index + step
        guard ids.indices.contains(target) else { return nil }
        var result = ids
        result.swapAt(index, target)
        return result
    }

    /// Inserts `newID` right after `sourceID` (duplicate lands next to its original).
    static func inserting(_ newID: UUID, after sourceID: UUID, in ids: [UUID]) -> [UUID] {
        var result = ids
        let index = result.firstIndex(of: sourceID).map { $0 + 1 } ?? result.endIndex
        result.insert(newID, at: index)
        return result
    }

    /// New `sortOrder` per card for `order` (0…n-1), limited to cards whose value changes.
    static func changes(from cards: [CardSummary], to order: [UUID]) -> [UUID: Int] {
        let current = Dictionary(cards.map { ($0.id, $0.sortOrder) }, uniquingKeysWith: { first, _ in first })
        var result: [UUID: Int] = [:]
        for (index, id) in order.enumerated() where current[id] != index {
            result[id] = index
        }
        return result
    }

    /// Sort order for a card appended at the end.
    static func nextSortOrder(after cards: [CardSummary]) -> Int {
        (cards.map(\.sortOrder).max() ?? -1) + 1
    }
}
