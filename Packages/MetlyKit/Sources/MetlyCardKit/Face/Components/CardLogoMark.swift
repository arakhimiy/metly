import MetlyCore
import SwiftUI

/// The owner's logo, fitted into a box: as uploaded, or one-colour in `ink` (foil, deboss, the card's
/// ink) when the card's logo style is One-colour and the image has a transparent background.
struct CardLogoMark<Ink: ShapeStyle>: View {
    let data: Data
    let style: CardLogoStyle
    let ink: Ink
    let width: CGFloat
    let height: CGFloat
    var alignment: Alignment = .center

    var body: some View {
        if let image = CardImageDecoder.image(from: data) {
            Group {
                if style == .mono, CardImageDecoder.hasTransparency(data) {
                    Image(uiImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(ink)
                } else {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: width, maxHeight: height, alignment: alignment)
            .frame(width: width, height: height, alignment: alignment)
            .accessibilityHidden(true)
        }
    }
}

/// Contacts as a two-column `label  value` block (`tel`, `mail`, `web`) — the printed-card convention,
/// instead of an icon per line.
struct CardLabelledContacts: View {
    let contacts: [CardFaceModel.Contact]
    let style: CardFaceStyle
    var fontSize: CGFloat = 2.7
    var labelColor: Color?
    var valueColor: Color?
    var spacing: CGFloat = 1.1
    var font: ((CGFloat) -> Font)?

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: style.u(2.4), verticalSpacing: style.u(spacing)) {
            ForEach(contacts) { contact in
                GridRow {
                    Text(verbatim: contact.terminalKey)
                        .font(textFont(fontSize * 0.86))
                        .foregroundStyle(labelColor ?? style.muted)
                        .lineLimit(1)
                        .fixedSize()
                    Text(verbatim: contact.value)
                        .font(textFont(fontSize))
                        .monospacedDigit()
                        .foregroundStyle(valueColor ?? style.fg)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
        }
    }

    private func textFont(_ size: CGFloat) -> Font { font?(size) ?? style.font(size) }
}

/// Contact values only, one per line (Monogram, Foil, Editorial).
struct CardPlainContacts: View {
    let contacts: [CardFaceModel.Contact]
    let style: CardFaceStyle
    var fontSize: CGFloat = 2.7
    var weight: Font.Weight = .regular
    var spacing: CGFloat = 1
    var color: Color?
    var font: Font?

    var body: some View {
        VStack(alignment: .leading, spacing: style.u(spacing)) {
            ForEach(contacts) { contact in
                CardContactValue(contact: contact, style: style, fontSize: fontSize, weight: weight, font: font)
                    .foregroundStyle(color ?? style.fg)
            }
        }
    }
}

/// Outlined capitals (the ink of the letters is the card colour): eight offset copies in `stroke`
/// under one copy in `fill`. SwiftUI has no text stroke; at card sizes this reads as a clean outline.
struct CardOutlinedText: View {
    let text: String
    let font: Font
    let tracking: CGFloat
    let stroke: Color
    let fill: Color
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<8, id: \.self) { index in
                let angle = Double(index) * .pi / 4
                label.foregroundStyle(stroke)
                    .offset(x: cos(angle) * lineWidth, y: sin(angle) * lineWidth)
            }
            label.foregroundStyle(fill)
        }
        .accessibilityHidden(true)
    }

    private var label: some View {
        Text(verbatim: text.uppercased()).font(font).tracking(tracking).lineLimit(1).minimumScaleFactor(0.3)
    }
}
