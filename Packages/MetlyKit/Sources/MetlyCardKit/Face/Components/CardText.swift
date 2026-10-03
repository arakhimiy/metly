import SwiftUI

/// A line of card-face text with a size and tracking expressed in card-width percentages.
struct CardText: View {
    let text: String
    let style: CardFaceStyle
    /// Font size, % of card width.
    let size: CGFloat
    var weight: Font.Weight = .regular
    /// CSS letter-spacing, em.
    var tracking: CGFloat = 0
    var color: Color?
    var lineLimit = 1
    /// Names shrink a little before they truncate; secondary lines just truncate.
    var minimumScale: CGFloat = 1
    var uppercase = false

    var body: some View {
        Text(verbatim: uppercase ? text.uppercased() : text)
            .font(style.font(size, weight: weight))
            .tracking(style.tracking(tracking, size: size))
            .foregroundStyle(color ?? style.fg)
            .lineLimit(lineLimit)
            .truncationMode(.tail)
            .minimumScaleFactor(minimumScale)
    }
}
