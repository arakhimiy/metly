import SwiftUI

/// Resolved colours for one palette in one appearance, plus the derived tones from SPEC §4.2.
public struct CardPaletteColors: Hashable, Sendable {
    public let background: CardRGB
    public let foreground: CardRGB
    public let accent: CardRGB

    public init(background: CardRGB, foreground: CardRGB, accent: CardRGB) {
        self.background = background
        self.foreground = foreground
        self.accent = accent
    }

    /// Secondary text: foreground 66 % mixed into background.
    public var muted: CardRGB { foreground.mixed(into: background, amount: 0.66) }

    /// Avatar circles: accent 24 % mixed into background.
    public var panelTint: CardRGB { accent.mixed(into: background, amount: 0.24) }

    /// End stop of the gradient fill: accent 40 % mixed into background.
    public var gradientEnd: CardRGB { accent.mixed(into: background, amount: 0.40) }

    /// Hairlines and outlined pills: foreground at 24 % alpha.
    public var rule: Color { foreground.color(opacity: 0.24) }

    /// Card fill, solid or the 140° gradient (`bg 22% → accent 40% into bg`).
    func fill(gradient: Bool, size: CGSize) -> AnyShapeStyle {
        guard gradient else { return AnyShapeStyle(background.color) }
        return AnyShapeStyle(CardGradient.linear140(from: background, to: gradientEnd, size: size))
    }
}
