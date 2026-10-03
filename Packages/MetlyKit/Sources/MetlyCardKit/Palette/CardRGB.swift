import SwiftUI

/// An opaque sRGB colour used by card palettes.
///
/// Card faces are the one place in the app where fixed hex colours are allowed (SPEC §4.2).
/// Mixing happens in gamma-encoded sRGB, matching CSS `color-mix(in srgb, …)` from the prototype.
public struct CardRGB: Hashable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// `0xRRGGBB`.
    public init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// `self` at `amount` (0…1) mixed into `other` — CSS `color-mix(in srgb, self amount, other)`.
    public func mixed(into other: CardRGB, amount: Double) -> CardRGB {
        let t = min(max(amount, 0), 1)
        return CardRGB(red: red * t + other.red * (1 - t),
                       green: green * t + other.green * (1 - t),
                       blue: blue * t + other.blue * (1 - t))
    }

    public var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }

    public func color(opacity: Double) -> Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: opacity)
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
    }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio against another colour (1…21).
    public func contrastRatio(with other: CardRGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}
