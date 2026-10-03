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

    @Test func privateFieldsCanNeverBeShown() {
        let design = CardDesign(visibleFields: [])
        #expect(CardDesignRules.settingField(.phone, visible: true, privacy: .private, in: design) == .blocked(.privateField))
        // …even when the stored design still lists them (privacy changed in Profile later).
        #expect(!CardDesignRules.isFieldShown(.phone, privacy: .private, in: CardDesign(visibleFields: [.phone])))
    }

    @Test func fieldTogglesUpdateVisibleFields() {
        let design = CardDesign(visibleFields: [.email])
        #expect(CardDesignRules.settingField(.telegram, visible: true, privacy: .public, in: design)
                == .updated(CardDesign(visibleFields: [.email, .telegram])))
        #expect(CardDesignRules.settingField(.email, visible: false, privacy: .connections, in: design)
                == .updated(CardDesign(visibleFields: [])))
        // Hiding a private field is always fine.
        #expect(CardDesignRules.settingField(.phone, visible: false, privacy: .private, in: CardDesign(visibleFields: [.phone]))
                == .updated(CardDesign(visibleFields: [])))
    }

    @Test func densityHidesExtraFields() {
        let fields = [
            ContactField(kind: .phone, value: "1", privacy: .public),
            ContactField(kind: .email, value: "a@b.c", privacy: .public),
            ContactField(kind: .telegram, value: "@t", privacy: .connections),
            ContactField(kind: .website, value: "w.uz", privacy: .public),
            ContactField(kind: .linkedin, value: "", privacy: .public),        // empty → not counted
        ]
        let all: Set<ContactFieldKind> = Set(ContactFieldKind.allCases)
        #expect(CardDesignRules.fieldsHiddenByDensity(fields: fields, design: CardDesign(density: .minimal, visibleFields: all)) == 2)
        #expect(CardDesignRules.fieldsHiddenByDensity(fields: fields, design: CardDesign(density: .balanced, visibleFields: all)) == 1)
        #expect(CardDesignRules.fieldsHiddenByDensity(fields: fields, design: CardDesign(density: .detailed, visibleFields: all)) == 0)
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
