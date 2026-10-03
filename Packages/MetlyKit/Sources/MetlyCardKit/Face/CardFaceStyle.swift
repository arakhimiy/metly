import MetlyCore
import SwiftUI

/// Resolved visual parameters for one card face at one width.
/// Every length in Appendix B is a percentage of the card width (`cqw`); `u(_:)` converts it.
struct CardFaceStyle {
    let width: CGFloat
    let colors: CardPaletteColors
    let fontDesign: Font.Design
    let alignment: CardAlignment
    let gradientFill: Bool

    init(design: CardDesign, width: CGFloat) {
        self.width = width
        colors = design.colors
        fontDesign = switch design.effectiveFont {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
        alignment = design.effectiveAlignment
        gradientFill = design.usesGradientFill
    }

    var height: CGFloat { width / CardFaceView.aspectRatio }

    /// `percent` of the card width, in points.
    func u(_ percent: CGFloat) -> CGFloat { width * percent / 100 }

    /// Card typography: a fixed size relative to the card width (card faces never follow Dynamic Type).
    func font(_ percent: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: max(u(percent), 0.5), weight: weight, design: fontDesign)
    }

    /// CSS `letter-spacing` in `em` for text of `percent` size.
    func tracking(_ em: CGFloat, size percent: CGFloat) -> CGFloat { u(percent) * em }

    var fg: Color { colors.foreground.color }
    var bg: Color { colors.background.color }
    var accent: Color { colors.accent.color }
    var muted: Color { colors.muted.color }
    var panelTint: Color { colors.panelTint.color }
    var rule: Color { colors.rule }

    var isCentered: Bool { alignment == .center }
    var horizontalAlignment: HorizontalAlignment { isCentered ? .center : .leading }
    var textAlignment: TextAlignment { isCentered ? .center : .leading }
    var frameAlignment: Alignment { isCentered ? .center : .leading }

    /// 1 CSS px on the 340 px prototype card, never thinner than a hairline.
    var hairline: CGFloat { max(width / 340, 0.5) }

    /// Max width of a block that must not run under a bottom-right QR plate.
    /// Leading blocks use the spec width; centred blocks are kept symmetric around the QR's left edge.
    func bottomBlockWidth(spec percent: CGFloat, qrInset: CGFloat, qrSize: CGFloat, showsQR: Bool) -> CGFloat {
        guard isCentered, showsQR else { return u(percent) }
        let qrLeft = 100 - qrInset - qrSize
        return u(min(percent, max(2 * (qrLeft - 50) - 2, 24)))
    }
}
