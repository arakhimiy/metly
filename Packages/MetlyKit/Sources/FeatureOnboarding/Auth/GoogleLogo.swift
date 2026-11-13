import SwiftUI

/// The multicolour Google "G" for "Continue with Google", drawn as a vector so it stays sharp at every
/// Dynamic Type size. Brand colours are Google's own (a third-party mark, like the LinkedIn/WhatsApp tints
/// in `ContactFieldKind.tint`), so they don't follow the app accent or the colour scheme.
struct GoogleLogo: View {
    var body: some View {
        GoogleGShape()
            .fill(AngularGradient(stops: Self.stops, center: .center))
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
    }

    // Angles run clockwise from 3 o'clock: blue bar and right side, green bottom, yellow left, red top.
    private static let blue = Color(red: 0.26, green: 0.52, blue: 0.96)
    private static let green = Color(red: 0.20, green: 0.66, blue: 0.33)
    private static let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)
    private static let red = Color(red: 0.92, green: 0.26, blue: 0.21)
    private static let stops: [Gradient.Stop] = [
        .init(color: blue, location: 0.00),
        .init(color: blue, location: 0.10),
        .init(color: green, location: 0.24),
        .init(color: green, location: 0.36),
        .init(color: yellow, location: 0.50),
        .init(color: yellow, location: 0.58),
        .init(color: red, location: 0.72),
        .init(color: red, location: 1.00),
    ]
}

/// The "G": a thick ring open at the top right, plus the crossbar running from the centre to the right edge.
nonisolated private struct GoogleGShape: Shape {
    func path(in rect: CGRect) -> Path {
        let size = min(rect.width, rect.height)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = size / 2
        let inner = outer * 0.6
        let end = Angle.degrees(317)   // where the ring stops, leaving the top-right opening

        var path = Path()
        path.addArc(center: center, radius: outer, startAngle: .zero, endAngle: end, clockwise: false)
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: .zero, clockwise: true)
        path.closeSubpath()
        path.addRect(CGRect(x: center.x - size * 0.01, y: center.y - size * 0.09,
                            width: outer + size * 0.01, height: size * 0.195))
        return path
    }
}

#Preview("Google logo") {
    GoogleLogo().frame(width: 120, height: 120).padding()
}
