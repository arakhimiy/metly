import SwiftUI

/// Card outline: continuous rounded rectangle with a corner radius of 4.2 % of its width.
/// `inset` grows (positive) or shrinks the radius for rings drawn around a card.
public struct CardFaceShape: InsettableShape {
    public static let cornerFraction: CGFloat = 0.042

    var outset: CGFloat = 0
    var insetAmount: CGFloat = 0

    /// - Parameter outset: distance between the card edge and this outline (for selection rings).
    public init(outset: CGFloat = 0) {
        self.outset = outset
    }

    public func path(in rect: CGRect) -> Path {
        let cardWidth = max(rect.width - 2 * outset, 0)
        let radius = max(cardWidth * Self.cornerFraction + outset - insetAmount, 0)
        return Path(roundedRect: rect.insetBy(dx: insetAmount, dy: insetAmount), cornerRadius: radius, style: .continuous)
    }

    public func inset(by amount: CGFloat) -> CardFaceShape {
        var copy = self
        copy.insetAmount += amount
        return copy
    }
}
