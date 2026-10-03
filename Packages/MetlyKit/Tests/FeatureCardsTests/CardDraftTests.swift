import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import FeatureCards

@MainActor
struct CardDraftTests {
    @Test func freshDraftIsClean() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let draft = CardDraft(card: card)
        #expect(draft == CardDraft(card: card))
        #expect(!draft.changesMedia)
    }

    @Test func editingTheDraftLeavesTheCardUntouchedUntilApplied() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let original = CardDraft(card: card)
        var draft = original
        draft.design.palette = .sand
        draft.name = "Office"

        #expect(draft != original)          // dirty → Cancel asks to discard
        #expect(card.design.palette == .ink) // discarding = simply dropping the draft
        #expect(card.name == "Work")
        #expect(card.syncState == .synced)
    }

    @Test func applyWritesNameAndDesignAndMarksTheCardDirty() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let before = card.updatedAt
        var draft = CardDraft(card: card)
        draft.name = "  Conference  "
        draft.design.template = .bold

        let commit = draft.apply(to: card, profile: nil)

        #expect(commit == CardDraftCommit(cardChanged: true, profileChanged: false))
        #expect(card.name == "Conference")
        #expect(card.design.template == .bold)
        #expect(card.syncState == .pendingUpsert)
        #expect(card.updatedAt >= before)
    }

    @Test func applyingAnUnchangedDraftWritesNothing() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let profile = insertProfile(in: context)

        let commit = CardDraft(card: card).apply(to: card, profile: profile)

        #expect(!commit.changedAnything)
        #expect(card.syncState == .synced)
        #expect(profile.syncState == .synced)
    }

    @Test func blankNameKeepsTheStoredName() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        var draft = CardDraft(card: card)
        draft.name = "   "

        let commit = draft.apply(to: card, profile: nil)

        #expect(!commit.cardChanged)
        #expect(card.name == "Work")
    }

    @Test func mediaEditsGoToTheProfileOnApply() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let profile = insertProfile(in: context)
        profile.logoData = Data([9, 9])
        profile.syncState = .synced
        var draft = CardDraft(card: card)
        draft.photo = .replaced(Data([1, 2, 3]))
        draft.logo = .removed

        let commit = draft.apply(to: card, profile: profile)

        #expect(commit == CardDraftCommit(cardChanged: false, profileChanged: true))
        #expect(profile.photoData == Data([1, 2, 3]))
        #expect(profile.logoData == nil)
        #expect(profile.syncState == .pendingUpsert)
    }

    @Test func mediaEditResolution() {
        let current = Data([7])
        #expect(MediaEdit.unchanged.resolved(current) == current)
        #expect(MediaEdit.replaced(Data([1])).resolved(current) == Data([1]))
        #expect(MediaEdit.removed.resolved(current) == nil)
    }
}
