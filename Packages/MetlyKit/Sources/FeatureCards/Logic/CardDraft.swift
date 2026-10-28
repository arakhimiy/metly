import Foundation
import MetlyCore
import MetlyData

/// CARD_EDITOR works on this copy (SPEC §9 Q12): Cancel throws it away, Done applies it once.
nonisolated struct CardDraft: Equatable, Sendable {
    var name: String
    var design: CardDesign
    /// Profile entries the card shows (`Card.visibleContactIDs`); nil = a card from before 3.0.0 not changed yet.
    var contactIDs: [UUID]?
    /// Profile photo (shared by every card) — applied to `Profile.photoData` on Done.
    var photo: MediaEdit = .unchanged
    /// Profile logo (shared by every card) — applied to `Profile.logoData` on Done.
    var logo: MediaEdit = .unchanged

    init(name: String, design: CardDesign, contactIDs: [UUID]? = nil) {
        self.name = name
        self.design = design
        self.contactIDs = contactIDs
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var hasValidName: Bool { !trimmedName.isEmpty }

    var changesMedia: Bool { photo != .unchanged || logo != .unchanged }
}

/// What `CardDraft.apply` wrote.
nonisolated struct CardDraftCommit: Equatable, Sendable {
    var cardChanged: Bool
    var profileChanged: Bool

    var changedAnything: Bool { cardChanged || profileChanged }
}

extension CardDraft {
    @MainActor
    init(card: Card) {
        self.init(name: card.name, design: card.design, contactIDs: card.visibleContactIDs)
    }

    /// Writes the draft into the stored card (and profile media), marking only what really changed
    /// so the sync engine republishes the page / Wallet pass once.
    @MainActor
    @discardableResult
    func apply(to card: Card, profile: Profile?) -> CardDraftCommit {
        apply(to: card, profile: profile, since: CardDraft(card: card))
    }

    /// Like `apply(to:profile:)`, but writes only what the user changed relative to `original`
    /// (the copy taken when the editor opened). A rename or design that reached the card meanwhile —
    /// Card Settings committing its name field, or sync from another device — is kept, not reverted.
    @MainActor
    @discardableResult
    func apply(to card: Card, profile: Profile?, since original: CardDraft) -> CardDraftCommit {
        var cardChanged = false
        if hasValidName, trimmedName != original.trimmedName, trimmedName != card.name {
            card.name = trimmedName
            cardChanged = true
        }
        if design != original.design, design != card.design {
            card.design = design
            cardChanged = true
        }
        if contactIDs != original.contactIDs, contactIDs != card.visibleContactIDs {
            card.visibleContactIDs = contactIDs
            cardChanged = true
        }
        if cardChanged { card.markChanged() }

        var profileChanged = false
        if let profile {
            if photo != .unchanged, photo.resolved(profile.photoData) != profile.photoData {
                profile.photoData = photo.resolved(profile.photoData)
                profileChanged = true
            }
            if logo != .unchanged, logo.resolved(profile.logoData) != profile.logoData {
                profile.logoData = logo.resolved(profile.logoData)
                profileChanged = true
            }
            if profileChanged { profile.markChanged() }
        }
        return CardDraftCommit(cardChanged: cardChanged, profileChanged: profileChanged)
    }
}
