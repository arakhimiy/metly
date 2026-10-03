import MetlyCore
import SwiftUI

/// "Aa" sample of a card typeface with a selection ring (editor "Type").
struct TypefaceTile: View {
    let font: CardFont
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            Text(verbatim: "Aa")
                .font(.title2)
                .fontWeight(.semibold)
                .fontDesign(font.fontDesign)
            Text(font.title)
                .font(.footnote)
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, minHeight: 64)
        .padding(.vertical, 6)
        .background(.fill.tertiary, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        }
        .contentShape(.rect(cornerRadius: 10))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(font.title) typeface"))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}

extension CardFont {
    /// System font design matching the card typeface (SF Pro, SF Pro Rounded, New York, SF Mono).
    var fontDesign: Font.Design {
        switch self {
        case .system: .default
        case .rounded: .rounded
        case .serif: .serif
        case .mono: .monospaced
        }
    }
}
