import MetlyCore
import MetlyDesign
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
            contact.kind.icon
                .resizable()
                .scaledToFit()
                .frame(width: max(style.u(iconSize) * 0.85, 0.5), height: max(style.u(iconSize) * 0.85, 0.5))
                .foregroundStyle(iconColor)
                .frame(width: style.u(iconSize) * 1.15, height: style.u(iconSize))
            CardContactValue(contact: contact, style: style, fontSize: fontSize)
        }
    }
}

/// A contact value on one line. When the card shows several phone numbers, each one is followed by a
/// small muted label ("Work") that never truncates — the number ellipsizes first.
struct CardContactValue: View {
    let contact: CardFaceModel.Contact
    let style: CardFaceStyle
    /// Text size, % of card width.
    let fontSize: CGFloat
    var weight: Font.Weight = .regular
    /// Overrides the card font (Editorial's serif colophon).
    var font: Font?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: style.u(1)) {
            Text(verbatim: contact.value)
                .font(font ?? style.font(fontSize, weight: weight))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.tail)
            if let label = contact.phoneLabel {
                Text(verbatim: label.title)
                    .font(style.font(fontSize * 0.82))
                    .foregroundStyle(style.muted)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}
