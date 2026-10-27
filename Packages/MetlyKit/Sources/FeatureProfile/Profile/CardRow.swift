import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI
import MetlySharedUI

/// Cards row: 56 pt card face · name · link (or "Not published") · Default · ⌃⌄ → card menu.
struct CardRow: View {
    let card: Card
    let faceContent: CardFaceContent
    let isDefault: Bool
    let perform: (CardAction) -> Void

    var body: some View {
        Menu {
            CardActionsMenu(hasLink: card.url != nil, isDefault: isDefault, isReadOnly: card.isReadOnly, perform: perform)
        } label: {
            HStack(spacing: 12) {
                CardFaceView(design: card.design, content: faceContent)
                    .frame(width: 56)
                    // Hairline so light cards don't melt into the row background.
                    .overlay {
                        RoundedRectangle(cornerRadius: 56 * 0.042)
                            .strokeBorder(Color(.separator), lineWidth: 0.5)
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    // Explicit `Color`s: inside a Menu label hierarchical styles resolve to the tint.
                    Text(card.name)
                        .foregroundStyle(Color.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                if isDefault {
                    Text("Default")
                        .font(.subheadline)
                        .foregroundStyle(Color.secondary)
                }
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote)
                    .foregroundStyle(Color(.tertiaryLabel))
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
        }
        .accessibilityLabel("\(card.name) Card")
        .accessibilityValue(isDefault ? String(localized: "\(subtitle), Default") : subtitle)
        .accessibilityHint("Shows actions for this card")
    }

    private var subtitle: String {
        var parts: [String] = [card.slug.isEmpty ? String(localized: "Not published") : "\(Brand.linkHost)/c/\(card.slug)"]
        if card.isReadOnly { parts.append(String(localized: "Read-only")) }
        return parts.joined(separator: " · ")
    }
}
