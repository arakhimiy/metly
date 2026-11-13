import SwiftUI

/// The isometric illustrations used by `EmptyStateView`. Drawn in code (no bitmaps), so they stay
/// sharp at every size, follow light/dark mode, and use the app accent (system Blue).
public enum EmptyStateArt: Sendable {
    /// Two people swapping a card: no connections yet.
    case connections
    /// A stack of cards with a "+" tile: no card yet.
    case cards
    /// A calendar block with a check tile: no follow-ups yet.
    case followUps
    /// A flag on a small stage with two people: no events yet.
    case events
    /// A spreadsheet block with an arrow: nothing to export.
    case export
    /// A barrier: nobody blocked.
    case blocked
}

/// The illustration on its own. Decorative: hidden from VoiceOver (the title says it all).
public struct IsometricArtView: View {
    let art: EmptyStateArt

    public init(_ art: EmptyStateArt) {
        self.art = art
    }

    public var body: some View {
        Canvas { context, size in
            var iso = IsoCanvas(context: context, size: size)
            IsoScenes.draw(art, on: &iso)
        }
        .aspectRatio(IsoCanvas.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

// MARK: - Projection

/// A 2:1-style isometric projection onto a Canvas. Scene units: x and y run along the floor
/// (a 4×4 platform from 0 to 4), z points up. Faces are shaded from one base colour:
/// top = base, left (+y) = a little darker, right (+x) = darker still.
nonisolated struct IsoCanvas {
    var context: GraphicsContext
    let unit: CGFloat
    let origin: CGPoint

    // Visible window in projected units (see `project`), wide enough for the platform and the tallest scene.
    static let minX: CGFloat = -3.7, maxX: CGFloat = 3.7
    static let minY: CGFloat = -2.1, maxY: CGFloat = 4.45
    static var aspectRatio: CGFloat { (maxX - minX) / (maxY - minY) }

    private static let cos30: CGFloat = 0.8660254
    private static let sin30: CGFloat = 0.5

    init(context: GraphicsContext, size: CGSize) {
        self.context = context
        unit = min(size.width / (Self.maxX - Self.minX), size.height / (Self.maxY - Self.minY))
        let drawnWidth = (Self.maxX - Self.minX) * unit
        let drawnHeight = (Self.maxY - Self.minY) * unit
        origin = CGPoint(x: (size.width - drawnWidth) / 2 - Self.minX * unit,
                         y: (size.height - drawnHeight) / 2 - Self.minY * unit)
    }

    func project(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + (x - y) * Self.cos30 * unit,
                y: origin.y + ((x + y) * Self.sin30 - z) * unit)
    }

    private func polygon(_ points: [(CGFloat, CGFloat, CGFloat)]) -> Path {
        var path = Path()
        let projected = points.map { project($0.0, $0.1, $0.2) }
        path.addLines(projected)
        path.closeSubpath()
        return path
    }

    // MARK: Shapes

    /// A solid block with its corner at (x, y, z).
    mutating func box(_ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                      w: CGFloat, d: CGFloat, h: CGFloat, color: Color) {
        let top = z + h
        context.fill(polygon([(x, y + d, z), (x + w, y + d, z), (x + w, y + d, top), (x, y + d, top)]),
                     with: .color(color.mix(with: .black, by: 0.12)))
        context.fill(polygon([(x + w, y, z), (x + w, y + d, z), (x + w, y + d, top), (x + w, y, top)]),
                     with: .color(color.mix(with: .black, by: 0.24)))
        context.fill(polygon([(x, y, top), (x + w, y, top), (x + w, y + d, top), (x, y + d, top)]),
                     with: .color(color))
    }

    /// A flat rectangle lying on the plane at height z (decoration on a top face).
    mutating func floorRect(_ x: CGFloat, _ y: CGFloat, z: CGFloat, w: CGFloat, d: CGFloat, color: Color) {
        context.fill(polygon([(x, y, z), (x + w, y, z), (x + w, y + d, z), (x, y + d, z)]), with: .color(color))
    }

    /// A flat rectangle standing upright, facing +y (a flag, a sign).
    mutating func wallRect(_ x: CGFloat, y: CGFloat, _ z: CGFloat, w: CGFloat, h: CGFloat, color: Color) {
        context.fill(polygon([(x, y, z), (x + w, y, z), (x + w, y, z + h), (x, y, z + h)]), with: .color(color))
    }

    /// A soft, flat shadow under an object.
    mutating func shadow(_ cx: CGFloat, _ cy: CGFloat, z: CGFloat, radius: CGFloat) {
        context.fill(ellipse(cx, cy, z: z, radius: radius), with: .color(.black.opacity(0.10)))
    }

    /// A horizontal circle of radius r around (cx, cy) at height z, as projected (an ellipse).
    func ellipse(_ cx: CGFloat, _ cy: CGFloat, z: CGFloat, radius r: CGFloat) -> Path {
        let center = project(cx, cy, z)
        let a = 1.2247449 * r * unit   // √2·cos30
        let b = 0.7071068 * r * unit   // √2·sin30
        return Path(ellipseIn: CGRect(x: center.x - a, y: center.y - b, width: a * 2, height: b * 2))
    }

    /// An upright cylinder (a person's body).
    mutating func cylinder(_ cx: CGFloat, _ cy: CGFloat, _ z: CGFloat, radius r: CGFloat, h: CGFloat, color: Color) {
        let a = 1.2247449 * r * unit
        let bottom = project(cx, cy, z), top = project(cx, cy, z + h)
        var side = Path()
        side.addRect(CGRect(x: bottom.x - a, y: top.y, width: a * 2, height: bottom.y - top.y))
        side.addPath(ellipse(cx, cy, z: z, radius: r))
        context.fill(side, with: .linearGradient(
            Gradient(colors: [color.mix(with: .black, by: 0.08), color.mix(with: .black, by: 0.28)]),
            startPoint: CGPoint(x: bottom.x - a, y: 0), endPoint: CGPoint(x: bottom.x + a, y: 0)))
        context.fill(ellipse(cx, cy, z: z + h, radius: r), with: .color(color.mix(with: .white, by: 0.12)))
    }

    /// A ball resting with its centre at (cx, cy, cz).
    mutating func sphere(_ cx: CGFloat, _ cy: CGFloat, _ cz: CGFloat, radius r: CGFloat, color: Color) {
        let center = project(cx, cy, cz)
        let radius = r * unit
        let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.fill(Path(ellipseIn: rect), with: .radialGradient(
            Gradient(colors: [color.mix(with: .white, by: 0.25), color.mix(with: .black, by: 0.2)]),
            center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4),
            startRadius: 0, endRadius: radius * 1.5))
    }

    /// A person: body + head, standing on the floor at (cx, cy, z).
    mutating func person(_ cx: CGFloat, _ cy: CGFloat, z: CGFloat = 0, scale s: CGFloat = 1, color: Color, skin: Color) {
        shadow(cx, cy, z: z, radius: 0.42 * s)
        cylinder(cx, cy, z, radius: 0.32 * s, h: 0.78 * s, color: color)
        sphere(cx, cy, z + 1.05 * s, radius: 0.26 * s, color: skin)
    }

    /// A strip of short lines on a top face, like text on a card.
    mutating func textLines(_ x: CGFloat, _ y: CGFloat, z: CGFloat, widths: [CGFloat], color: Color) {
        for (index, width) in widths.enumerated() {
            floorRect(x, y + CGFloat(index) * 0.2, z: z, w: width, d: 0.08, color: color)
        }
    }
}

// MARK: - Palette

nonisolated private enum IsoPalette {
    static let platform = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.24, alpha: 1) : UIColor(white: 0.90, alpha: 1) })
    static let surface = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.36, alpha: 1) : UIColor(white: 0.99, alpha: 1) })
    static let ink = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(white: 0.62, alpha: 1) : UIColor(white: 0.78, alpha: 1) })
    static let accent = Color.accentColor
    static let second = Color(uiColor: .systemIndigo)
    static let warm = Color(uiColor: .systemOrange)
    static let skin = Color(red: 0.96, green: 0.80, blue: 0.66)
    static let skinDeep = Color(red: 0.72, green: 0.52, blue: 0.38)
}

// MARK: - Scenes

nonisolated private enum IsoScenes {
    static func draw(_ art: EmptyStateArt, on iso: inout IsoCanvas) {
        platform(&iso)
        switch art {
        case .connections: connections(&iso)
        case .cards: cards(&iso)
        case .followUps: followUps(&iso)
        case .events: events(&iso)
        case .export: export(&iso)
        case .blocked: blocked(&iso)
        }
    }

    /// The floor tile every scene stands on, with a faint accent inset.
    private static func platform(_ iso: inout IsoCanvas) {
        iso.box(0, 0, -0.3, w: 4, d: 4, h: 0.3, color: IsoPalette.platform)
        iso.floorRect(0.25, 0.25, z: 0, w: 3.5, d: 3.5, color: IsoPalette.accent.opacity(0.07))
    }

    /// A business card lying flat: white slab, accent band, two text lines.
    private static func card(_ iso: inout IsoCanvas, _ x: CGFloat, _ y: CGFloat, _ z: CGFloat,
                             w: CGFloat = 1.7, d: CGFloat = 1.1, body: Color = IsoPalette.surface, band: Color = IsoPalette.accent) {
        iso.box(x, y, z, w: w, d: d, h: 0.09, color: body)
        let top = z + 0.09
        iso.floorRect(x, y, z: top, w: w, d: 0.22, color: band)
        iso.textLines(x + 0.18, y + 0.42, z: top, widths: [w * 0.5, w * 0.34], color: IsoPalette.ink)
        iso.floorRect(x + w - 0.48, y + d - 0.48, z: top, w: 0.32, d: 0.32, color: IsoPalette.ink)
    }

    private static func connections(_ iso: inout IsoCanvas) {
        iso.person(0.9, 2.9, color: IsoPalette.accent, skin: IsoPalette.skin)
        iso.shadow(2.0, 2.0, z: 0, radius: 0.7)
        card(&iso, 1.2, 1.5, 0.75, w: 1.5, d: 0.95)
        iso.person(2.9, 0.9, color: IsoPalette.second, skin: IsoPalette.skinDeep)
    }

    private static func cards(_ iso: inout IsoCanvas) {
        // Back to front: the "+" tile sits behind the stack.
        // "+" tile
        iso.box(2.85, 0.55, 0, w: 0.75, d: 0.75, h: 0.35, color: IsoPalette.accent)
        iso.floorRect(3.12, 0.66, z: 0.35, w: 0.2, d: 0.53, color: .white)
        iso.floorRect(2.96, 0.82, z: 0.35, w: 0.53, d: 0.2, color: .white)
        iso.shadow(1.9, 2.0, z: 0, radius: 1.1)
        card(&iso, 1.0, 1.4, 0.0, w: 2.0, d: 1.3, body: IsoPalette.surface, band: IsoPalette.second)
        card(&iso, 0.95, 1.35, 0.22, w: 2.0, d: 1.3, body: IsoPalette.surface, band: IsoPalette.warm)
        card(&iso, 0.9, 1.3, 0.44, w: 2.0, d: 1.3)
    }

    private static func followUps(_ iso: inout IsoCanvas) {
        // Check tile.
        iso.box(3.0, 0.5, 0, w: 0.8, d: 0.8, h: 0.6, color: IsoPalette.accent)
        let base = iso.project(3.25, 0.95, 0.6), mid = iso.project(3.4, 1.1, 0.6), tip = iso.project(3.62, 0.66, 0.6)
        var check = Path()
        check.addLines([base, mid, tip])
        iso.context.stroke(check, with: .color(.white), style: StrokeStyle(lineWidth: max(1.5, iso.unit * 0.09),
                                                                         lineCap: .round, lineJoin: .round))
        // Calendar block: accent header strip and a grid of days.
        iso.box(0.8, 1.2, 0, w: 2.0, d: 2.0, h: 0.45, color: IsoPalette.surface)
        iso.floorRect(0.8, 1.2, z: 0.45, w: 2.0, d: 0.4, color: IsoPalette.accent)
        for row in 0..<3 {
            for column in 0..<4 {
                let highlighted = row == 1 && column == 2
                iso.floorRect(0.98 + CGFloat(column) * 0.44, 1.78 + CGFloat(row) * 0.44, z: 0.45, w: 0.26, d: 0.26,
                              color: highlighted ? IsoPalette.warm : IsoPalette.ink)
            }
        }
    }

    private static func events(_ iso: inout IsoCanvas) {
        // Stage.
        iso.box(0.6, 0.6, 0, w: 2.2, d: 1.6, h: 0.25, color: IsoPalette.surface)
        // Flag: pole + cloth.
        iso.box(1.0, 1.0, 0.25, w: 0.1, d: 0.1, h: 2.1, color: IsoPalette.ink)
        iso.wallRect(1.1, y: 1.05, 1.65, w: 1.1, h: 0.65, color: IsoPalette.accent)
        iso.wallRect(1.1, y: 1.05, 1.85, w: 1.1, h: 0.12, color: .white.opacity(0.55))
        iso.person(1.4, 3.2, scale: 0.85, color: IsoPalette.warm, skin: IsoPalette.skin)
        iso.person(3.2, 2.6, scale: 0.85, color: IsoPalette.second, skin: IsoPalette.skinDeep)
    }

    private static func export(_ iso: inout IsoCanvas) {
        // Arrow tile pointing out of the block.
        iso.box(3.05, 0.6, 0, w: 0.8, d: 0.8, h: 0.5, color: IsoPalette.second)
        var arrow = Path()
        arrow.addLines([iso.project(3.2, 1.0, 0.5), iso.project(3.7, 1.0, 0.5)])
        arrow.addLines([iso.project(3.5, 0.82, 0.5), iso.project(3.7, 1.0, 0.5), iso.project(3.5, 1.18, 0.5)])
        iso.context.stroke(arrow, with: .color(.white), style: StrokeStyle(lineWidth: max(1.5, iso.unit * 0.09),
                                                                         lineCap: .round, lineJoin: .round))
        // Spreadsheet block.
        iso.box(0.7, 1.0, 0, w: 2.2, d: 2.2, h: 0.35, color: IsoPalette.surface)
        iso.floorRect(0.7, 1.0, z: 0.35, w: 2.2, d: 0.35, color: IsoPalette.accent)
        for row in 0..<4 {
            iso.floorRect(0.85, 1.55 + CGFloat(row) * 0.38, z: 0.35, w: 0.55, d: 0.16, color: IsoPalette.ink)
            iso.floorRect(1.55, 1.55 + CGFloat(row) * 0.38, z: 0.35, w: 1.15, d: 0.16, color: IsoPalette.ink.opacity(0.7))
        }
    }

    private static func blocked(_ iso: inout IsoCanvas) {
        // Two posts and a striped bar between them.
        iso.box(0.9, 2.2, 0, w: 0.3, d: 0.3, h: 1.2, color: IsoPalette.surface)
        iso.box(2.9, 0.2, 0, w: 0.3, d: 0.3, h: 1.2, color: IsoPalette.surface)
        let stripes = 6
        for index in 0..<stripes {
            let t0 = CGFloat(index) / CGFloat(stripes), t1 = CGFloat(index + 1) / CGFloat(stripes)
            let x0 = 1.05 + 2.0 * t0, x1 = 1.05 + 2.0 * t1
            let y0 = 2.35 - 2.0 * t0, y1 = 2.35 - 2.0 * t1
            var band = Path()
            band.addLines([iso.project(x0, y0, 0.85), iso.project(x1, y1, 0.85),
                           iso.project(x1, y1, 1.15), iso.project(x0, y0, 1.15)])
            band.closeSubpath()
            iso.context.fill(band, with: .color(index.isMultiple(of: 2) ? IsoPalette.warm : .white))
        }
        iso.person(2.6, 2.8, scale: 0.85, color: IsoPalette.accent, skin: IsoPalette.skin)
    }
}

#Preview("Isometric art") {
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], spacing: 24) {
            ForEach(Array([EmptyStateArt.connections, .cards, .followUps, .events, .export, .blocked].enumerated()),
                    id: \.offset) { _, art in
                IsometricArtView(art).frame(height: 140)
            }
        }
        .padding()
    }
}
