import Foundation
import MetlyCore
import MetlyData
import SwiftData
import Testing
@testable import FeatureConnect

struct CardChoiceTests {
    private let work = UUID()
    private let personal = UUID()
    private let event = UUID()

    @Test func requestedCardWins() {
        let id = CardChoice.initialCardID(requested: personal, cardToShare: work, liveCardIDs: [work, personal])
        #expect(id == personal)
    }

    @Test func deletedRequestedCardFallsBackToCardToShare() {
        let id = CardChoice.initialCardID(requested: UUID(), cardToShare: personal, liveCardIDs: [work, personal])
        #expect(id == personal)
    }

    @Test func fallsBackToFirstLiveCard() {
        #expect(CardChoice.initialCardID(requested: nil, cardToShare: nil, liveCardIDs: [work, personal]) == work)
        #expect(CardChoice.initialCardID(requested: nil, cardToShare: event, liveCardIDs: [personal]) == personal)
        #expect(CardChoice.initialCardID(requested: nil, cardToShare: nil, liveCardIDs: []) == nil)
    }

    @Test func validatedKeepsTheUsersChoice() {
        #expect(CardChoice.validated(personal, requested: nil, cardToShare: work, liveCardIDs: [work, personal]) == personal)
        // The chosen card was deleted meanwhile.
        #expect(CardChoice.validated(personal, requested: nil, cardToShare: work, liveCardIDs: [work]) == work)
    }

    // MARK: From the store (ModelContext.cardToShare)

    @MainActor
    private func store(defaultCard: Bool, eventCard: Bool) throws -> (ModelContext, work: Card, personal: Card) {
        let context = try makeContainer().mainContext
        let workCard = Card(name: "Work", sortOrder: 0)
        let personalCard = Card(name: "Personal", sortOrder: 1)
        let profile = Profile(fullName: "Aziza Karimova", isSetupComplete: true)
        context.insert(workCard)
        context.insert(personalCard)
        context.insert(profile)
        if defaultCard { profile.defaultCardID = personalCard.id }
        if eventCard {
            context.insert(Event(name: "Tashkent Tech Week", cardID: workCard.id))
        }
        try context.save()
        return (context, workCard, personalCard)
    }

    @Test @MainActor func activeEventCardBeatsDefaultCard() throws {
        let (context, work, _) = try store(defaultCard: true, eventCard: true)
        #expect(CardChoice.initialCardID(requested: nil, in: context) == work.id)
    }

    @Test @MainActor func defaultCardWithoutEvent() throws {
        let (context, _, personal) = try store(defaultCard: true, eventCard: false)
        #expect(CardChoice.initialCardID(requested: nil, in: context) == personal.id)
    }

    @Test @MainActor func firstCardWithoutDefault() throws {
        let (context, work, _) = try store(defaultCard: false, eventCard: false)
        #expect(CardChoice.initialCardID(requested: nil, in: context) == work.id)
    }

    @Test @MainActor func explicitCardOverridesEventCard() throws {
        let (context, _, personal) = try store(defaultCard: false, eventCard: true)
        #expect(CardChoice.initialCardID(requested: personal.id, in: context) == personal.id)
    }

    @Test @MainActor func deletedCardsAreNeverChosen() throws {
        let (context, work, personal) = try store(defaultCard: true, eventCard: false)
        personal.markDeleted()
        try context.save()
        #expect(CardChoice.initialCardID(requested: personal.id, in: context) == work.id)
    }
}
