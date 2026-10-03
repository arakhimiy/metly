import SwiftUI

/// The card face silhouette (corner radius = 4.2% of width, SPEC Appendix B).
struct CardOutline: InsettableShape {
    var insetAmount = 0.0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        return RoundedRectangle(cornerRadius: rect.width * 0.042).path(in: insetRect)
    }

    func inset(by amount: CGFloat) -> CardOutline {
        CardOutline(insetAmount: insetAmount + amount)
    }
}

extension View {
    /// Hairline edge so dark cards stay visible on a dark background (and light ones on light).
    func cardEdge() -> some View {
        overlay {
            CardOutline()
                .strokeBorder(.primary.opacity(0.14), lineWidth: 1)
        }
    }
}
