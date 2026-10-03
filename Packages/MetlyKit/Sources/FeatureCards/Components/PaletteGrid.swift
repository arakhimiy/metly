import MetlyCardKit
import MetlyCore
import SwiftUI

/// The 6 palette swatches (Ocean / Ember locked on Free). What happens on tap is up to the caller.
struct PaletteGrid: View {
    let design: CardDesign
    let allowsPro: Bool
    let onSelect: (CardPalette) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 8)], spacing: 8) {
            ForEach(CardPalette.allCases) { palette in
                Button {
                    onSelect(palette)
                } label: {
                    CardPaletteSwatch(palette: palette, appearance: design.appearance,
                                      isSelected: design.palette == palette,
                                      isLocked: CardDesignRules.isLocked(palette, allowsPro: allowsPro))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.selection, trigger: design.palette)
    }
}

/// "{Palette}. Text contrast meets WCAG AA." (the claim is only made when it holds).
struct PaletteFooter: View {
    let design: CardDesign

    var body: some View {
        if CardDesignRules.meetsContrastAA(design) {
            Text("\(design.palette.title). Text contrast meets WCAG AA.")
        } else {
            Text(design.palette.title)
        }
    }
}
