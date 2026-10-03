import SwiftUI

/// Vertical contacts list: SF Symbol + value per row, single line, tail-ellipsized.
struct CardContactList: View {
    let contacts: [CardFaceModel.Contact]
    let style: CardFaceStyle
    /// Row text size, % of card width.
    var fontSize: CGFloat = 3
    /// Icon size, % of card width.
    var iconSize: CGFloat = 3.3
    /// Gap between rows, % of card width.
    var spacing: CGFloat = 1
    /// Max block width, in points.
    let maxWidth: CGFloat
    /// Icons in accent (default) or foreground colour (Gradient template).
    var iconColor: Color?

    var body: some View {
        CardCapWidth(maxWidth: maxWidth) {
            VStack(alignment: .leading, spacing: style.u(spacing)) {
                ForEach(contacts) { contact in
                    CardContactRow(contact: contact, style: style, fontSize: fontSize, iconSize: iconSize,
                                   iconColor: iconColor ?? style.accent)
                }
            }
        }
    }
}

struct CardContactRow: View {
    let contact: CardFaceModel.Contact
    let style: CardFaceStyle
    let fontSize: CGFloat
    let iconSize: CGFloat
    let iconColor: Color

    var body: some View {
        HStack(spacing: style.u(1.8)) {
            Image(systemName: contact.kind.symbolName)
                .font(.system(size: max(style.u(iconSize) * 0.9, 0.5)))
                .foregroundStyle(iconColor)
                .frame(width: style.u(iconSize) * 1.15, height: style.u(iconSize))
            Text(verbatim: contact.value)
                .font(style.font(fontSize))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
