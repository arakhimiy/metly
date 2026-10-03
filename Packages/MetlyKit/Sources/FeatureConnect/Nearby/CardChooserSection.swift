import MetlyCardKit
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
                    row(showsChevron: true)
                }
                .disabled(isLocked)
                .accessibilityLabel("Card to Share")
                .accessibilityValue(selectedCard.map { "\($0.name) card" } ?? "None")
                .accessibilityHint("Choose which card people you connect with receive")
            } else {
                row(showsChevron: false)
                    .accessibilityElement(children: .combine)
            }
        } header: {
            Text("Sharing")
        } footer: {
            if let selectedCard {
                Text(ConnectCopy.sharingFooter(selectedCard.name))
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
        .task(id: thumbnailKey) { renderThumbnails() }
    }

    private var selectedCard: Card? {
        cards.first { $0.id == selection } ?? cards.first
    }

    private func row(showsChevron: Bool) -> some View {
        HStack(spacing: 12) {
            if let selectedCard {
                CardFaceView(design: selectedCard.design,
                             content: selectedCard.faceContent(profile: profile, audience: .connections))
                    .frame(width: 64)
                    .cardFaceElevation()
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(selectedCard.name) Card")
                        .font(.body)
                        .foregroundStyle(.primary)
                    if let url = selectedCard.url {
                        Text(url.host().map { "\($0)\(url.path())" } ?? url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } else {
                Text("No card yet")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
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
