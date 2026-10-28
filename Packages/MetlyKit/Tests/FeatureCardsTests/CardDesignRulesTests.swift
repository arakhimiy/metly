import MetlyCore
import Testing
@testable import FeatureCards

struct CardDesignRulesTests {
    @Test func editorialNeedsProOnFree() {
        let outcome = CardDesignRules.selecting(.editorial, in: CardDesign(), allowsPro: false)
        #expect(outcome == .requiresPro(.proTemplate))
    }

    @Test func editorialIsFreeToPickOnPro() {
        guard case .updated(let design) = CardDesignRules.selecting(.editorial, in: CardDesign(), allowsPro: true) else {
            Issue.record("expected an update")
            return
        }
        #expect(design.template == .editorial)
    }

    @Test func keepingAnAlreadyAppliedProTemplateIsAllowed() {
        let downgraded = CardDesign(template: .editorial)
        #expect(CardDesignRules.selecting(.editorial, in: downgraded, allowsPro: false) == .updated(downgraded))
    }

    @Test func proPalettesNeedPro() {
        #expect(CardDesignRules.selecting(.ocean, in: CardDesign(), allowsPro: false) == .requiresPro(.proPalette))
        #expect(CardDesignRules.selecting(.ember, in: CardDesign(), allowsPro: false) == .requiresPro(.proPalette))
        guard case .updated(let design) = CardDesignRules.selecting(.sand, in: CardDesign(), allowsPro: false) else {
            Issue.record("Sand is free")
            return
        }
        #expect(design.palette == .sand)
    }

    @Test func gradientTemplateForcesGradientBackground() {
        guard case .updated(let design) = CardDesignRules.selecting(.gradient, in: CardDesign(background: .solid), allowsPro: false) else {
            Issue.record("expected an update")
            return
        }
        #expect(design.background == .gradient)
        #expect(CardDesignRules.settingGradient(false, in: design) == .blocked(.gradientTemplateIsAlwaysGradient))
    }

    @Test func gradientToggleOnOtherTemplates() {
        let design = CardDesign(template: .minimal, background: .solid)
        #expect(CardDesignRules.settingGradient(true, in: design) == .updated(CardDesign(template: .minimal, background: .gradient)))
    }

    @Test func privateEntriesCanNeverBeShown() {
        let phone = ContactEntry(kind: .phone, value: "1", privacy: .private)
        #expect(CardDesignRules.settingContact(phone, visible: true, in: []) == .blocked(.privateField))
        // Hiding one is always fine.
        #expect(CardDesignRules.settingContact(phone, visible: false, in: [phone.id]) == .updated([]))
    }

    @Test func togglesUpdateTheSelection() {
        let email = ContactEntry(kind: .email, value: "a@b.c", privacy: .public)
        let whatsapp = ContactEntry(kind: .whatsapp, value: "90 1", privacy: .connections)
        #expect(CardDesignRules.settingContact(whatsapp, visible: true, in: [email.id]) == .updated([email.id, whatsapp.id]))
        #expect(CardDesignRules.settingContact(email, visible: false, in: [email.id, whatsapp.id]) == .updated([whatsapp.id]))
        #expect(CardDesignRules.settingContact(email, visible: true, in: [email.id]) == .updated([email.id]))
    }

    @Test func densityHidesExtraEntries() {
        let entries = [
            ContactEntry(kind: .phone, value: "1", privacy: .public),
            ContactEntry(kind: .email, value: "a@b.c", privacy: .public),
            ContactEntry(kind: .telegram, value: "@t", privacy: .connections),
            ContactEntry(kind: .phone, label: .work, value: "2", privacy: .public),
            ContactEntry(kind: .instagram, value: "@i", privacy: .private),      // Private → not counted
        ]
        #expect(CardDesignRules.hiddenByDensity(entries, design: CardDesign(density: .minimal)) == (fields: 1, phones: 1))
        #expect(CardDesignRules.hiddenByDensity(entries, design: CardDesign(density: .balanced)) == (fields: 0, phones: 1))
        #expect(CardDesignRules.hiddenByDensity(entries, design: CardDesign(density: .detailed)) == (fields: 0, phones: 0))
    }

    @Test func everyPaletteMeetsContrastAA() {
        for palette in CardPalette.allCases {
            for appearance in CardAppearance.allCases {
                #expect(CardDesignRules.meetsContrastAA(CardDesign(palette: palette, appearance: appearance)))
            }
        }
    }

    @Test func locks() {
        #expect(CardDesignRules.isLocked(CardTemplate.editorial, allowsPro: false))
        #expect(!CardDesignRules.isLocked(CardTemplate.editorial, allowsPro: true))
        #expect(!CardDesignRules.isLocked(CardTemplate.minimal, allowsPro: false))
        #expect(CardDesignRules.isLocked(CardPalette.ocean, allowsPro: false))
        #expect(!CardDesignRules.isLocked(CardPalette.ink, allowsPro: false))
    }
}
