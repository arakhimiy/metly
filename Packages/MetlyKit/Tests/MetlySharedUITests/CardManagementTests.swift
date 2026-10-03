import Foundation
import MetlyCore
import Testing
@testable import MetlySharedUI

@Suite("Card management rules")
struct CardManagementTests {
    let work = CardSummary(id: UUID(), sortOrder: 0)
    let personal = CardSummary(id: UUID(), sortOrder: 1)
    let event = CardSummary(id: UUID(), sortOrder: 2)

    @Test func lastCardCanNeverBeDeleted() {
        #expect(CardManagement.planDeletion(of: work.id, cards: [work], defaultID: work.id) == .blockedLastCard)
    }

    @Test func deletingANonDefaultCardKeepsTheDefault() {
        let plan = CardManagement.planDeletion(of: personal.id, cards: [work, personal], defaultID: work.id)
        #expect(plan == .delete(newDefaultID: nil))
    }

    @Test func deletingTheDefaultPromotesTheFirstRemainingCard() {
        let plan = CardManagement.planDeletion(of: work.id, cards: [event, personal, work], defaultID: work.id)
        #expect(plan == .delete(newDefaultID: personal.id))
    }

    @Test func implicitDefaultIsTheFirstCardBySortOrder() {
        #expect(CardManagement.effectiveDefaultID(cards: [personal, work], defaultID: nil) == work.id)
        // A stale default (deleted card) falls back the same way.
        #expect(CardManagement.effectiveDefaultID(cards: [personal, work], defaultID: UUID()) == work.id)
        #expect(CardManagement.effectiveDefaultID(cards: [], defaultID: nil) == nil)
    }

    @Test func deletingTheImplicitDefaultAlsoReassigns() {
        let plan = CardManagement.planDeletion(of: work.id, cards: [work, personal], defaultID: nil)
        #expect(plan == .delete(newDefaultID: personal.id))
    }

    @Test(arguments: [(0, true), (1, true), (2, false), (5, false)])
    func freePlanAllowsTwoCards(existing: Int, allowed: Bool) {
        #expect(CardManagement.canCreateCard(existingCount: existing, limits: .free) == allowed)
    }

    @Test func proPlanHasNoCardLimit() {
        #expect(CardManagement.canCreateCard(existingCount: 50, limits: .pro))
    }
}
