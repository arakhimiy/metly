import MetlyData
import SwiftUI

/// "Card to Share" — inline picker with live card thumbnails. While the event is active this card
/// replaces the default card in Connect, QR and share flows (`modelContext.cardToShare()`).
struct CardToShareSection: View {
    let cards: [Card]
    let profile: Profile?
    @Binding var selection: UUID?

    var body: some View {
        Section {
            if cards.isEmpty {
                Text("No cards yet")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Card to Share", selection: $selection) {
                    ForEach(cards) { card in
                        CardOptionLabel(card: card, profile: profile, isDefault: card.id == profile?.defaultCardID)
                            .tag(Optional(card.id))
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
        } header: {
            Text("Card to Share")
        } footer: {
            Text("Everyone you connect with by QR, Nearby, your web page or a paper card is added to this event. It ends by itself after the last day and shows you a summary.")
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct CardOptionLabel: View {
    let card: Card
    let profile: Profile?
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 12) {
            EventCardThumbnail(card: card, profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(card.name)
                if isDefault {
                    Text("Default Card")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}
