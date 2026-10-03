import Foundation
import MetlyCore
import SwiftUI
import Testing
@testable import MetlyCardKit

@Suite("Card palettes")
struct CardPaletteTests {
    static let combinations = CardPalette.allCases.flatMap { palette in
        CardAppearance.allCases.map { (palette, $0) }
    }

    @Test func matchesSpecTable() {
        let ink = CardPalette.ink.colors(.light)
        #expect(ink.background == CardRGB(hex: 0xFFFFFF))
        #expect(ink.foreground == CardRGB(hex: 0x0A1F44))
        #expect(ink.accent == CardRGB(hex: 0x1D4ED8))
        let ember = CardPalette.ember.colors(.dark)
        #expect(ember.background == CardRGB(hex: 0x1B0B08))
        #expect(ember.accent == CardRGB(hex: 0xF87171))
    }

    @Test func derivesMutedPanelTintAndGradientEnd() {
        let colors = CardPalette.snow.colors(.light)   // fg black on white bg
        #expect(abs(colors.muted.red - 0.34) < 0.0001)          // fg 66 % into bg
        #expect(abs(colors.panelTint.red - 0.76) < 0.0001)      // accent 24 % into bg
        #expect(abs(colors.gradientEnd.green - 0.60) < 0.0001)  // accent 40 % into bg
    }

    @Test(arguments: combinations)
    func textMeetsWCAGAA(_ palette: CardPalette, _ appearance: CardAppearance) {
        let colors = palette.colors(appearance)
        #expect(colors.foreground.contrastRatio(with: colors.background) >= 4.5)
        #expect(colors.muted.contrastRatio(with: colors.background) >= 4.5)
        #expect(colors.accent.contrastRatio(with: colors.background) >= 3)
    }

    @Test func gradientFollowsCSS140Degrees() {
        let (start, end) = CardGradient.points(angleDegrees: 140, size: CGSize(width: 85, height: 55))
        #expect(abs(start.x - 0.134) < 0.002 && abs(start.y - -0.174) < 0.002)
        #expect(abs(end.x - 0.866) < 0.002 && abs(end.y - 1.174) < 0.002)
        let (down, _) = CardGradient.points(angleDegrees: 180, size: CGSize(width: 10, height: 10))
        #expect(abs(down.x - 0.5) < 0.0001 && abs(down.y) < 0.0001)
    }
}
