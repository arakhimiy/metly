import MetlyCore
import SwiftUI

// Printed-card finishes drawn in code (docs/design/card-templates-v2.md §2.4): foil, deboss, contour lines
// and paper grain. Pure SwiftUI so they render the same in the app, widgets, `ImageRenderer` and print.

/// Foil stamping colour, chosen from the palette.
enum CardFoil {
    case holographic, gold, silver, rose

    /// The iridescent foil of the Foil template.
    static func holographic(for palette: CardPalette) -> CardFoil {
        switch palette {
        case .ink, .ocean, .graphite, .snow: .holographic
        case .sand: .gold
        case .ember: .rose
        }
    }

    /// The metal foil of the Editorial template.
    static func metal(for palette: CardPalette, appearance: CardAppearance) -> CardFoil {
        switch palette {
        case .sand: .gold
        case .ember: .rose
        case .graphite, .snow, .ink, .ocean: appearance == .light ? .gold : .silver
        }
    }

    private var stops: [Gradient.Stop] {
        func stop(_ hex: UInt32, _ location: CGFloat) -> Gradient.Stop {
            .init(color: CardRGB(hex: hex).color, location: location)
        }
        return switch self {
        case .holographic:
            [stop(0xF7D58B, 0), stop(0xF39BC3, 0.28), stop(0xC39BFF, 0.5), stop(0x7FE3FF, 0.72), stop(0xB9FFD8, 1)]
        case .gold:
            [stop(0xA77B2C, 0), stop(0xF3DC9A, 0.25), stop(0xB08A3C, 0.48), stop(0xF6E3A8, 0.68), stop(0x9C7429, 1)]
        case .silver:
            [stop(0xB8BEC6, 0), stop(0xFFFFFF, 0.22), stop(0x9DA4AD, 0.46), stop(0xF5F7F9, 0.64), stop(0xA9B0B8, 1)]
        case .rose:
            [stop(0xB76E79, 0), stop(0xF7CAC9, 0.26), stop(0xA85D68, 0.5), stop(0xF9D5D3, 0.7), stop(0x9E5560, 1)]
        }
    }

    var gradient: LinearGradient {
        LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// A foil-filled rectangle with a soft specular band, like hot-foil stamping under light.
struct CardFoilBlock: View {
    let foil: CardFoil
    var cornerRadius: CGFloat = 0

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(foil.gradient)
            .overlay {
                LinearGradient(stops: [
                    .init(color: .white.opacity(0), location: 0.36),
                    .init(color: .white.opacity(0.5), location: 0.5),
                    .init(color: .white.opacity(0), location: 0.62),
                ], startPoint: .topLeading, endPoint: .bottomTrailing)
                .blendMode(.softLight)
            }
            .clipShape(.rect(cornerRadius: cornerRadius, style: .continuous))
    }
}

extension CardFaceStyle {
    /// Card-coloured fill with an inner shadow pair: content pressed into the stock (blind deboss).
    var debossStyle: some ShapeStyle {
        let depth = max(u(0.45), 0.5)
        let isDark = colors.background.isDark
        return bg
            .shadow(.inner(color: .black.opacity(isDark ? 0.95 : 0.28), radius: depth, x: depth, y: depth))
            .shadow(.inner(color: .white.opacity(isDark ? 0.2 : 0.9), radius: depth, x: -depth, y: -depth))
    }
}

/// Fine offset sine contours (the Aurora template's line art).
nonisolated struct CardContourLines: View {
    let lineWidth: CGFloat
    var count = 18

    var body: some View {
        Canvas { context, size in
            for k in 0..<count {
                var path = Path()
                let base = size.height * (CGFloat(k) / CGFloat(count - 1))
                let k = CGFloat(k)
                var x: CGFloat = 0
                while x <= size.width {
                    let t = x / size.width
                    let y = base + sin(t * 5.2 + k * 0.35) * size.height * 0.07 + cos(t * 2.1 - k * 0.2) * size.height * 0.05
                    if x == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
                    x += max(size.width / 120, 1)
                }
                context.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: lineWidth)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Seeded noise dots that read as uncoated / matte stock. Skipped on small faces (thumbnails, widgets).
nonisolated struct CardPaperGrain: View {
    let isDark: Bool
    let dotSize: CGFloat

    /// Below this width the grain is invisible anyway; skipping it keeps widgets and grids fast.
    static let minimumWidth: CGFloat = 160

    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(UInt32.max >> 1)
            }
            let light = Color.white.opacity(isDark ? 0.06 : 0.35)
            let dark = Color.black.opacity(isDark ? 0.22 : 0.05)
            for index in 0..<1600 {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: dotSize, height: dotSize)
                context.fill(Path(rect), with: .color(index.isMultiple(of: 2) ? light : dark))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Fixed three-stop gradients for Aurora, curated per palette (vivid on dark, pastel on light).
enum CardAurora {
    static func colors(_ palette: CardPalette, _ appearance: CardAppearance) -> [CardRGB] {
        let hexes: [UInt32] = switch palette {
        case .ink: [0x7C3AED, 0xEC4899, 0xF97316]
        case .ocean: [0x4F46E5, 0x0EA5A4, 0xA3E635]
        case .ember: [0xBE123C, 0xF97316, 0xFBBF24]
        case .sand: [0x9A3412, 0xEA580C, 0xD97706]
        case .graphite: [0x1F2937, 0x64748B, 0xCBD5E1]
        case .snow: [0x0A0A0A, 0x3F3F46, 0xA1A1AA]
        }
        let rgb = hexes.map(CardRGB.init(hex:))
        guard appearance == .light else { return rgb }
        let white = CardRGB(hex: 0xFFFFFF)
        return rgb.map { $0.mixed(into: white, amount: 0.55) }
    }

    /// Text on the gradient: white on the vivid set, the palette's ink on the pastel one.
    static func foreground(_ design: CardDesign) -> Color {
        design.appearance == .light ? design.colors.foreground.color : .white
    }
}

/// Aurora's full-bleed fill: two soft colour pools over a diagonal three-stop gradient, plus contours.
struct CardAuroraFill: View {
    let design: CardDesign
    /// Card width, points (the colour pools scale with it).
    let width: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        let c = CardAurora.colors(design.palette, design.appearance)
        ZStack {
            LinearGradient(colors: c.map(\.color), startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [c[0].color, c[0].color.opacity(0)], center: .topLeading, startRadius: 0, endRadius: width * 1.0)
            RadialGradient(colors: [c[2].color, c[2].color.opacity(0)], center: .bottomTrailing, startRadius: 0, endRadius: width * 0.9)
            CardContourLines(lineWidth: lineWidth)
                .blendMode(.softLight)
        }
    }
}

extension CardRGB {
    /// Relative luminance under 0.4 (sRGB, approximate).
    var isDark: Bool { 0.2126 * red + 0.7152 * green + 0.0722 * blue < 0.4 }
}
