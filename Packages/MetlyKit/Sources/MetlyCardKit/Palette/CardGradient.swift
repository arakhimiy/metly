import SwiftUI

/// CSS-accurate `linear-gradient(140deg, a 22%, b)` for an arbitrary box.
enum CardGradient {
    static func linear140(from start: CardRGB, to end: CardRGB, size: CGSize) -> LinearGradient {
        let (startPoint, endPoint) = points(angleDegrees: 140, size: size)
        return LinearGradient(stops: [
            .init(color: start.color, location: 0.22),
            .init(color: end.color, location: 1),
        ], startPoint: startPoint, endPoint: endPoint)
    }

    /// CSS gradient line: centred, direction measured clockwise from "to top",
    /// length `|w·sin a| + |h·cos a|`, expressed in unit coordinates of the box.
    static func points(angleDegrees: Double, size: CGSize) -> (UnitPoint, UnitPoint) {
        let w = max(size.width, 1), h = max(size.height, 1)
        let radians = angleDegrees * .pi / 180
        let dx = sin(radians), dy = -cos(radians)   // screen space, y grows downwards
        let half = (abs(w * dx) + abs(h * dy)) / 2
        let ux = dx * half / w, uy = dy * half / h
        return (UnitPoint(x: 0.5 - ux, y: 0.5 - uy), UnitPoint(x: 0.5 + ux, y: 0.5 + uy))
    }
}
