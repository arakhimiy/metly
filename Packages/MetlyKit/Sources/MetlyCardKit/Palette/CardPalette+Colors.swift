import MetlyCore

// Palette definitions — SPEC §4.2 table, `[background, foreground, accent]` per appearance.

public extension CardPalette {
    func colors(_ appearance: CardAppearance) -> CardPaletteColors {
        let (bg, fg, acc): (UInt32, UInt32, UInt32) = switch (self, appearance) {
        case (.graphite, .light): (0xF5F5F7, 0x111114, 0x1C1C1E)
        case (.graphite, .dark): (0x0B0B0C, 0xF5F5F7, 0xFFFFFF)
        case (.snow, .light): (0xFFFFFF, 0x000000, 0x000000)
        case (.snow, .dark): (0x000000, 0xFFFFFF, 0xFFFFFF)
        case (.ink, .light): (0xFFFFFF, 0x0A1F44, 0x1D4ED8)
        case (.ink, .dark): (0x08111F, 0xE8EEF9, 0x60A5FA)
        case (.sand, .light): (0xF7F2EA, 0x2B2118, 0xA05A16)
        case (.sand, .dark): (0x1A1410, 0xF5EFE6, 0xF59E0B)
        case (.ocean, .light): (0xF0F9FF, 0x06283D, 0x0369A1)
        case (.ocean, .dark): (0x041B2B, 0xE0F2FE, 0x38BDF8)
        case (.ember, .light): (0xFFF7F5, 0x3A1410, 0xC02626)
        case (.ember, .dark): (0x1B0B08, 0xFFEDE9, 0xF87171)
        }
        return CardPaletteColors(background: CardRGB(hex: bg), foreground: CardRGB(hex: fg), accent: CardRGB(hex: acc))
    }
}

public extension CardDesign {
    /// Colours of this design's palette in its appearance.
    var colors: CardPaletteColors { palette.colors(appearance) }

    /// The gradient template always uses the gradient fill (SPEC Appendix B).
    var usesGradientFill: Bool { template == .gradient || background == .gradient }

    /// Terminal forces SF Mono and Editorial forces New York; others use the chosen font.
    var effectiveFont: CardFont {
        switch template {
        case .terminal: .mono
        case .editorial: .serif
        default: font
        }
    }

    /// Alignment is honoured by Minimal, Bold and Gradient only.
    var effectiveAlignment: CardAlignment {
        switch template {
        case .minimal, .bold, .gradient: alignment
        default: .leading
        }
    }

    /// Whether the chosen template renders the profile photo (Modern, Split, Stack).
    var templateShowsPhoto: Bool { [.modern, .split, .stack].contains(template) }

    /// Whether the chosen template renders the logo (Professional).
    var templateShowsLogo: Bool { template == .professional }

    /// Whether the user's font choice has an effect (not for Terminal / Editorial).
    var templateAllowsFontChoice: Bool { template != .terminal && template != .editorial }

    /// Whether the alignment control has an effect for the chosen template.
    var templateAllowsAlignment: Bool { [.minimal, .bold, .gradient].contains(template) }
}
