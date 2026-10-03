import Foundation
import MetlySharedUI
import Testing
@testable import FeatureCards

struct CardOrderingTests {
    private let a = UUID(), b = UUID(), c = UUID(), d = UUID()

    @Test func orderedIDsFollowSortOrder() {
        let cards = [CardSummary(id: a, sortOrder: 2), CardSummary(id: b, sortOrder: 0), CardSummary(id: c, sortOrder: 1)]
        #expect(CardOrdering.orderedIDs(cards) == [b, c, a])
    }

    @Test func listMoveDown() {
        // Drag A below C: onMove(from: [0], to: 3)
        #expect(CardOrdering.moving([a, b, c, d], fromOffsets: [0], toOffset: 3) == [b, c, a, d])
    }

    @Test func listMoveUp() {
        #expect(CardOrdering.moving([a, b, c, d], fromOffsets: [3], toOffset: 1) == [a, d, b, c])
    }

    @Test func listMoveToEndAndMultipleRows() {
        #expect(CardOrdering.moving([a, b, c, d], fromOffsets: [0], toOffset: 4) == [b, c, d, a])
        #expect(CardOrdering.moving([a, b, c, d], fromOffsets: [0, 2], toOffset: 4) == [b, d, a, c])
        #expect(CardOrdering.moving([a, b, c, d], fromOffsets: [1], toOffset: 1) == [a, b, c, d])
    }

    @Test func stepMovesStopAtTheEnds() {
        #expect(CardOrdering.moving(b, by: -1, in: [a, b, c]) == [b, a, c])
        #expect(CardOrdering.moving(b, by: 1, in: [a, b, c]) == [a, c, b])
        #expect(CardOrdering.moving(a, by: -1, in: [a, b, c]) == nil)
        #expect(CardOrdering.moving(c, by: 1, in: [a, b, c]) == nil)
        #expect(CardOrdering.moving(d, by: 1, in: [a, b, c]) == nil)
    }

    @Test func duplicateLandsRightAfterItsOriginal() {
        #expect(CardOrdering.inserting(d, after: a, in: [a, b, c]) == [a, d, b, c])
        #expect(CardOrdering.inserting(d, after: c, in: [a, b, c]) == [a, b, c, d])
        #expect(CardOrdering.inserting(d, after: UUID(), in: [a, b]) == [a, b, d])
    }

    @Test func changesOnlyReportCardsThatMoved() {
        let cards = [CardSummary(id: a, sortOrder: 0), CardSummary(id: b, sortOrder: 1), CardSummary(id: c, sortOrder: 2)]
        #expect(CardOrdering.changes(from: cards, to: [a, c, b]) == [c: 1, b: 2])
        #expect(CardOrdering.changes(from: cards, to: [a, b, c]).isEmpty)
    }

    @Test func changesRenormaliseGaps() {
        let cards = [CardSummary(id: a, sortOrder: 0), CardSummary(id: b, sortOrder: 5), CardSummary(id: c, sortOrder: 9)]
        #expect(CardOrdering.changes(from: cards, to: [a, b, c]) == [b: 1, c: 2])
    }

    @Test func nextSortOrderAppends() {
        #expect(CardOrdering.nextSortOrder(after: []) == 0)
        #expect(CardOrdering.nextSortOrder(after: [CardSummary(id: a, sortOrder: 0), CardSummary(id: b, sortOrder: 3)]) == 4)
    }
}
