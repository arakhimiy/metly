import MetlyCore
import MetlyData
import SwiftUI

/// "Sharing" — which card people you connect with receive (SPEC §2.5.26 card chooser, Q47/Q48).
/// A menu with small card-face thumbnails; a plain row when there's only one card.
struct CardChooserSection: View {
    let cards: [Card]
    let profile: Profile?
    @Binding var selection: UUID?
    var isLocked: Bool

    @Environment(\.displayScale) private var displayScale
    @State private var thumbnails: [UUID: UIImage] = [:]

    var body: some View {
        Section {
            if cards.count > 1 {
                Menu {
                    Picker("Card to Share", selection: $selection) {
                        ForEach(cards) { card in
                            Label {
                                Text(card.name)
                            } icon: {
                                if let image = thumbnails[card.id] {
                                    Image(uiImage: image)
                                } else {
                                    Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                                }
                            }
                            .tag(Optional(card.id))
                        }
                    }
                } label: {
                    CardChooserRow(card: selectedCard, profile: profile, showsChevron: true)
                }
                .disabled(isLocked)
                .accessibilityLabel("Card to Share")
                .accessibilityValue(selectedCard.map { "\($0.name) card" } ?? "None")
                .accessibilityHint("Choose which card people you connect with receive")
            } else {
                CardChooserRow(card: selectedCard, profile: profile, showsChevron: false)
                    .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Sharing")
        } footer: {
            if let selectedCard {
                Text(ConnectCopy.sharingFooter(selectedCard.name))
            }
        }
        .sensoryFeedback(trigger: selection) { previous, _ in
            // Not when the initial card is filled in, only when the user picks another one.
            previous.map { _ in SensoryFeedback.selection }
        }
        .task(id: thumbnailKey) { renderThumbnails() }
    }

    private var selectedCard: Card? {
        cards.first { $0.id == selection } ?? cards.first
    }

    private var thumbnailKey: [String] {
        cards.map { "\($0.id)-\($0.design.hashValue)" }
    }

    private func renderThumbnails() {
        var images: [UUID: UIImage] = [:]
        for card in cards {
            images[card.id] = CardThumbnail.image(for: card, profile: profile, scale: displayScale)
        }
        thumbnails = images
    }
}
