import Foundation
import MetlyCore
import MetlyData

/// CARD_EDITOR works on this copy (SPEC §9 Q12): Cancel throws it away, Done applies it once.
nonisolated struct CardDraft: Equatable, Sendable {
    var name: String
    var design: CardDesign
    /// Profile photo (shared by every card) — applied to `Profile.photoData` on Done.
    var photo: MediaEdit = .unchanged
    /// Profile logo (shared by every card) — applied to `Profile.logoData` on Done.
    var logo: MediaEdit = .unchanged

    init(name: String, design: CardDesign) {
        self.name = name
        self.design = design
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
        self.init(name: card.name, design: card.design)
    }

    /// Writes the draft into the stored card (and profile media), marking only what really changed
    /// so the sync engine republishes the page / Wallet pass once.
    @MainActor
    @discardableResult
    func apply(to card: Card, profile: Profile?) -> CardDraftCommit {
        var cardChanged = false
        if hasValidName, trimmedName != card.name {
            card.name = trimmedName
            cardChanged = true
        }
        if design != card.design {
            card.design = design
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
