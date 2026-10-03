import Foundation
import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftData
import Testing
@testable import FeatureCards

@MainActor
struct CardLibraryTests {
    @Test func firstCardBecomesTheDefault() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)

        let card = CardLibrary.create(name: " Work ", design: CardDesign(), in: context)

        #expect(card.name == "Work")
        #expect(card.sortOrder == 0)
        #expect(card.slug.isEmpty)                 // the server assigns it on publish
        #expect(card.syncState == .pendingUpsert)
        #expect(profile.defaultCardID == card.id)
    }

    @Test func laterCardsAppendWithoutChangingTheDefault() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let work = insertCard("Work", sortOrder: 0, in: context)
        profile.defaultCardID = work.id
        _ = insertCard("Personal", sortOrder: 3, in: context)

        let card = CardLibrary.create(name: "Conference", design: CardDesign(template: .bold), in: context)

        #expect(card.sortOrder == 4)
        #expect(card.design.template == .bold)
        #expect(profile.defaultCardID == work.id)
    }

    @Test func duplicateCopiesTheDesignNextToTheOriginal() throws {
        let context = try makeContext()
        let work = insertCard("Work", sortOrder: 0, slug: "aziza-w7k2",
                              design: CardDesign(template: .split, palette: .sand), in: context)
        let personal = insertCard("Personal", sortOrder: 1, in: context)

        let copy = CardLibrary.duplicate(work, in: context)

        #expect(copy.name == "Work Copy")
        #expect(copy.design == work.design)
        #expect(copy.slug.isEmpty)                 // new slug from the server
        #expect(copy.sortOrder == 1)
        #expect(personal.sortOrder == 2)
        #expect(personal.syncState == .pendingUpsert)
        #expect(work.sortOrder == 0)
        #expect(work.syncState == .synced)         // untouched
    }

    @Test func duplicatingTwiceNumbersTheCopies() throws {
        let context = try makeContext()
        let work = insertCard("Work", sortOrder: 0, in: context)
        let first = CardLibrary.duplicate(work, in: context)
        let second = CardLibrary.duplicate(work, in: context)
        let third = CardLibrary.duplicate(first, in: context)
        #expect(first.name == "Work Copy")
        #expect(second.name == "Work Copy 2")
        #expect(third.name == "Work Copy 3")
    }

    @Test func freePlanAllowsTwoCards() {
        #expect(CardManagement.canCreateCard(existingCount: 1, limits: .free))
        #expect(!CardManagement.canCreateCard(existingCount: 2, limits: .free))   // create + duplicate blocked
        #expect(CardManagement.canCreateCard(existingCount: 25, limits: .pro))
    }

    @Test func applyOrderTouchesOnlyMovedCards() throws {
        let context = try makeContext()
        let a = insertCard("A", sortOrder: 0, in: context)
        let b = insertCard("B", sortOrder: 1, in: context)
        let c = insertCard("C", sortOrder: 2, in: context)

        CardLibrary.applyOrder([a.id, c.id, b.id], to: [a, b, c])

        #expect(a.sortOrder == 0)
        #expect(b.sortOrder == 2)
        #expect(c.sortOrder == 1)
        #expect(a.syncState == .synced)
        #expect(b.syncState == .pendingUpsert)
        #expect(c.syncState == .pendingUpsert)
    }

    @Test func defaultFollowsTheEffectiveDefault() throws {
        let context = try makeContext()
        let profile = insertProfile(in: context)
        let work = insertCard("Work", sortOrder: 0, in: context)
        let personal = insertCard("Personal", sortOrder: 1, in: context)

        // No stored default → the first card by order.
        #expect(CardLibrary.isDefault(work, among: [work, personal], profile: profile))
        CardLibrary.setDefault(personal, profile: profile)
        #expect(CardLibrary.isDefault(personal, among: [work, personal], profile: profile))
        #expect(!CardLibrary.isDefault(work, among: [work, personal], profile: profile))
        #expect(profile.syncState == .pendingUpsert)
    }
}
