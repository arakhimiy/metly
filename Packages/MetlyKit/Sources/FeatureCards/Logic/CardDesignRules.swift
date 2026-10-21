import MetlyCardKit
import MetlyCore

/// Card design constraints shared by CARD_CREATE and CARD_EDITOR (SPEC §3.5, Appendix B).
///
/// - Editorial template and Ocean / Ember palettes are Pro.
/// - Gradient template forces the gradient background.
/// - Terminal / Editorial set their own typeface (`CardDesign.effectiveFont` in CardKit).
/// - Private fields can't be shown.
nonisolated enum CardDesignRules {
    static func selecting(_ template: CardTemplate, in design: CardDesign, allowsPro: Bool) -> DesignOutcome {
        // Keeping an already-applied Pro template (e.g. after a downgrade) is allowed.
        if template.isPro, !allowsPro, design.template != template { return .requiresPro(.proTemplate) }
        var updated = design
        updated.template = template
        if template == .gradient { updated.background = .gradient }
        return .updated(updated)
    }

    static func selecting(_ palette: CardPalette, in design: CardDesign, allowsPro: Bool) -> DesignOutcome {
        if palette.isPro, !allowsPro, design.palette != palette { return .requiresPro(.proPalette) }
        var updated = design
        updated.palette = palette
        return .updated(updated)
    }

    /// "Duplicate Card": the copy keeps the design. A Free user may still own a Pro-designed card
    /// (kept after a downgrade), but a duplicate is a new card, so its Pro template / palette is gated.
    static func duplicating(_ design: CardDesign, allowsPro: Bool) -> DesignOutcome {
        if !allowsPro, design.template.isPro { return .requiresPro(.proTemplate) }
        if !allowsPro, design.palette.isPro { return .requiresPro(.proPalette) }
        return .updated(design)
    }

    static func settingGradient(_ isOn: Bool, in design: CardDesign) -> DesignOutcome {
        if !isOn, design.template == .gradient { return .blocked(.gradientTemplateIsAlwaysGradient) }
        var updated = design
        updated.background = isOn ? .gradient : .solid
        return .updated(updated)
    }

    static func settingField(_ kind: ContactFieldKind, visible: Bool, privacy: FieldPrivacy,
                             in design: CardDesign) -> DesignOutcome {
        if visible, privacy == .private { return .blocked(.privateField) }
        var updated = design
        if visible {
            updated.visibleFields.insert(kind)
        } else {
            updated.visibleFields.remove(kind)
        }
        return .updated(updated)
    }

    /// Whether a field's toggle is on: design-visible and not Private.
    static func isFieldShown(_ kind: ContactFieldKind, privacy: FieldPrivacy, in design: CardDesign) -> Bool {
        privacy != .private && design.visibleFields.contains(kind)
    }

    static func isLocked(_ template: CardTemplate, allowsPro: Bool) -> Bool { template.isPro && !allowsPro }

    static func isLocked(_ palette: CardPalette, allowsPro: Bool) -> Bool { palette.isPro && !allowsPro }

    /// How many shown, non-empty fields the density hides (e.g. 4 shown on Balanced → 1 hidden).
    static func fieldsHiddenByDensity(fields: [ContactField], design: CardDesign) -> Int {
        let shown = fields.count(where: {
            !$0.isEmpty && isFieldShown($0.kind, privacy: $0.privacy, in: design)
        })
        return max(shown - design.density.maxContacts, 0)
    }

    /// WCAG AA for normal text (4.5 : 1) between the palette's text and background.
    static func meetsContrastAA(_ design: CardDesign) -> Bool {
        let colors = design.colors
        return colors.foreground.contrastRatio(with: colors.background) >= 4.5
    }
}
