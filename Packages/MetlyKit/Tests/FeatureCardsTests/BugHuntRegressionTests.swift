import Foundation
import MetlyCore
import MetlyData
import Testing
@testable import FeatureCards

/// Regression tests for bugs found in the Cards & Sharing bug hunt (one test per failure scenario).
@MainActor
struct BugHuntRegressionTests {
    // MARK: Editor Done must not clobber changes made outside the editor

    /// Card Settings commits a typed name when it loses focus — after the editor (opened with
    /// "Edit Design") already copied the old name. The editor has no name field, so Done must not
    /// write the stale name back. The same happens with a rename synced from another device.
    @Test func editorDoneKeepsARenameThatLandedWhileEditing() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let original = CardDraft(card: card)
        var draft = original
        draft.design.template = .bold

        card.name = "Conference"
        let commit = draft.apply(to: card, profile: nil, since: original)

        #expect(card.name == "Conference")
        #expect(card.design.template == .bold)
        #expect(commit.cardChanged)
    }

    /// Done after editing only the photo must not revert a design synced while the editor was open.
    @Test func editorDoneWithoutDesignEditsKeepsADesignSyncedMeanwhile() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        let profile = insertProfile(in: context)
        let original = CardDraft(card: card)
        var draft = original
        draft.photo = .replaced(Data([1, 2]))

        card.design.palette = .sand
        card.syncState = .synced
        let commit = draft.apply(to: card, profile: profile, since: original)

        #expect(card.design.palette == .sand)
        #expect(card.syncState == .synced)
        #expect(commit == CardDraftCommit(cardChanged: false, profileChanged: true))
        #expect(profile.photoData == Data([1, 2]))
    }

    // MARK: Read-only cards (Pro downgrade beyond the Free limit)

    @Test func readOnlyCardsCannotBeRenamedFromCardSettings() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        card.isReadOnly = true

        #expect(!CardLibrary.rename(card, to: "Office"))
        #expect(card.name == "Work")
        #expect(card.syncState == .synced)
    }

    @Test func renameTrimsAndMarksTheCardDirty() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)

        #expect(!CardLibrary.rename(card, to: "   "))
        #expect(!CardLibrary.rename(card, to: " Work "))
        #expect(card.syncState == .synced)

        #expect(CardLibrary.rename(card, to: "  Office "))
        #expect(card.name == "Office")
        #expect(card.syncState == .pendingUpsert)
    }

    @Test func deletedCardsCannotBeRenamed() throws {
        let context = try makeContext()
        let card = insertCard("Work", sortOrder: 0, in: context)
        card.markDeleted()
        #expect(!CardLibrary.rename(card, to: "Office"))
        #expect(card.name == "Work")
    }

    // MARK: Pro locks

    /// A Free user can still hold an Editorial / Ocean / Ember card after a downgrade. Duplicating it
    /// must not mint a new card with a Pro design.
    @Test func duplicatingAProDesignOnFreeRequiresPro() {
        #expect(CardDesignRules.duplicating(CardDesign(template: .editorial), allowsPro: false) == .requiresPro(.proTemplate))
        #expect(CardDesignRules.duplicating(CardDesign(palette: .ocean), allowsPro: false) == .requiresPro(.proPalette))
        #expect(CardDesignRules.duplicating(CardDesign(palette: .ember), allowsPro: false) == .requiresPro(.proPalette))
    }

    @Test func duplicatingIsUnrestrictedForFreeDesignsAndOnPro() {
        let free = CardDesign(template: .split, palette: .sand)
        let pro = CardDesign(template: .editorial, palette: .ocean)
        #expect(CardDesignRules.duplicating(free, allowsPro: false) == .updated(free))
        #expect(CardDesignRules.duplicating(pro, allowsPro: true) == .updated(pro))
    }

    // MARK: CARD_CREATE card limit

    /// "See Pro" on the Free card-limit alert used to *replace* CARD_CREATE with the paywall: after a
    /// purchase the user landed on Home, and a limit hit at Publish threw the whole wizard away.
    /// The paywall must stack on the wizard, so closing it (`router.dismiss()`) returns there.
    @Test func seeProFromTheCardLimitKeepsTheWizardUnderThePaywall() {
        let router = AppRouter(phase: .main)
        router.present(.cardCreate(origin: .home))

        CardCreateFlow.showLimitPaywall(router: router)
        #expect(router.presentations == [.cover(.cardCreate(origin: .home)), .cover(.paywall(trigger: .cardLimit))])

        router.dismiss()   // the paywall closes itself this way after a purchase
        #expect(router.presentations == [.cover(.cardCreate(origin: .home))])
    }

    /// Back from the paywall still on Free: the alert comes back instead of letting the user build a
    /// card that Publish will refuse. Never once the card exists (the success screen is up).
    @Test func cardLimitAlertIsReshownOnlyWhileTheLimitStillApplies() {
        #expect(CardCreateFlow.needsLimitAlert(canCreate: false, hasCreatedCard: false))
        #expect(!CardCreateFlow.needsLimitAlert(canCreate: true, hasCreatedCard: false))   // upgraded to Pro
        #expect(!CardCreateFlow.needsLimitAlert(canCreate: false, hasCreatedCard: true))   // just published the 2nd card
    }

    // MARK: QR_FULLSCREEN

    private var publicContent: CardFaceContent {
        CardFaceContent(fullName: "Aziza Karimova",
                        fields: [ContactField(kind: .website, value: "aziza.design", privacy: .public)])
    }

    private let url = Brand.cardURL(slug: "aziza-w7k2")

    /// A Wi-Fi blip at an event must not leave the screen on the contact-only vCard for good
    /// (no analytics, no share-back) once the connection is back.
    @Test func offlineQRSwitchesBackToTheLinkWhenTheNetworkReturns() {
        var preference: Bool? = nil
        preference = QRCodeMode.preference(afterConnectivityChange: preference, isOnline: false)
        #expect(QRCodeMode.resolve(url: url, isOnline: false, prefersOffline: preference, publicContent: publicContent).isOffline)

        preference = QRCodeMode.preference(afterConnectivityChange: preference, isOnline: true)
        #expect(QRCodeMode.resolve(url: url, isOnline: true, prefersOffline: preference, publicContent: publicContent) == .link(url))
    }

    @Test func losingTheNetworkStillOverridesAnExplicitLinkChoice() {
        let preference = QRCodeMode.preference(afterConnectivityChange: false, isOnline: false)
        #expect(QRCodeMode.resolve(url: url, isOnline: false, prefersOffline: preference, publicContent: publicContent).isOffline)
    }

    @Test func anExplicitOfflineChoiceSurvivesNetworkChanges() {
        var preference: Bool? = true
        preference = QRCodeMode.preference(afterConnectivityChange: preference, isOnline: false)
        preference = QRCodeMode.preference(afterConnectivityChange: preference, isOnline: true)
        #expect(QRCodeMode.resolve(url: url, isOnline: true, prefersOffline: preference, publicContent: publicContent).isOffline)
    }

    /// The card shown in QR_FULLSCREEN was deleted (another device, or a stale widget deep link):
    /// the chooser must move to the card actually on screen instead of keeping a dangling ID.
    @Test func qrSelectionMovesOffADeletedCard() {
        let work = UUID(), personal = UUID()
        #expect(QRCardSelection.resolve(personal, among: [work, personal]) == personal)
        #expect(QRCardSelection.resolve(UUID(), among: [work, personal]) == work)
        #expect(QRCardSelection.resolve(work, among: []) == nil)
    }
}
