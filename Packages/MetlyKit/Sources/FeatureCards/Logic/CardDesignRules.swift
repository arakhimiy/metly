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
    /// Every phone number counts as its own line, but only one line per kind is guaranteed (CardKit).
    static func fieldsHiddenByDensity(fields: [ContactField], additionalPhones: [LabeledPhone] = [],
                                      design: CardDesign) -> Int {
        contactLines(fields: fields, additionalPhones: additionalPhones, design: design).hiddenFieldCount
    }

    /// Extra phone numbers that are switched on but don't fit: they only use lines the other fields leave free.
    static func phonesHiddenByDensity(fields: [ContactField], additionalPhones: [LabeledPhone],
                                      design: CardDesign) -> Int {
        contactLines(fields: fields, additionalPhones: additionalPhones, design: design).hiddenPhoneCount
    }

    /// The owner's in-app view of the card (Public + Connections), as CardKit lays it out.
    private static func contactLines(fields: [ContactField], additionalPhones: [LabeledPhone],
                                     design: CardDesign) -> CardFaceModel.ContactLines {
        CardFaceModel.contactLines(
            from: CardContentFactory.fields(fields, visible: design.visibleFields, audience: .connections),
            additionalPhones: CardContentFactory.phones(additionalPhones, visible: design.visibleFields, audience: .connections),
            design: design)
    }

    // MARK: Phone numbers (one switch for every number)

    /// The privacy that decides whether "Phone Numbers" can be switched on: the most open number's.
    /// Only when every filled number is Private is the switch disabled. Without any number, the
    /// primary phone's privacy applies (its value can be typed in right there).
    static func phoneGroupPrivacy(primary: ContactField, additionalPhones: [LabeledPhone]) -> FieldPrivacy {
        let filled = ([primary].filter { !$0.isEmpty }.map(\.privacy)) + additionalPhones.filter { !$0.isEmpty }.map(\.privacy)
        if filled.isEmpty { return primary.privacy }
        if filled.contains(.public) { return .public }
        if filled.contains(.connections) { return .connections }
        return .private
    }

    /// Filled numbers that are Private: they never appear on a card even with the switch on.
    static func privatePhoneCount(primary: ContactField, additionalPhones: [LabeledPhone]) -> Int {
        ([primary].filter { !$0.isEmpty && $0.privacy == .private }.count)
            + additionalPhones.count { !$0.isEmpty && $0.privacy == .private }
    }

    /// WCAG AA for normal text (4.5 : 1) between the palette's text and background.
    static func meetsContrastAA(_ design: CardDesign) -> Bool {
        let colors = design.colors
        return colors.foreground.contrastRatio(with: colors.background) >= 4.5
    }
}
