import MetlyCardKit
import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftUI

/// Horizontally paging card faces with a system page indicator (hidden for a single card).
/// Scrolling sets the active card (`AppPreferences.activeCardID`).
struct CardCarousel: View {
    let cards: [Card]
    let profile: Profile?
    let defaultCardID: UUID?
    @Binding var selection: UUID?
    let onOpen: (Card) -> Void
    let onAction: (CardAction, Card) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 16) {
                    ForEach(cards) { card in
                        CardCarouselItem(card: card,
                                         content: card.faceContent(profile: profile, audience: .connections),
                                         isDefault: card.id == defaultCardID,
                                         onOpen: { onOpen(card) },
                                         onAction: { onAction($0, card) })
                            .containerRelativeFrame(.horizontal)
                            .id(card.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $selection)
            .scrollIndicators(.hidden)
            .scrollClipDisabled()

            if cards.count > 1 {
                PageIndicator(numberOfPages: cards.count, currentPage: currentPage, onSelect: select)
                    .accessibilityHidden(true) // the cards themselves are swipeable VoiceOver elements
            }
        }
        .padding(.vertical, 8)
    }

    private var currentPage: Int {
        cards.firstIndex { $0.id == selection } ?? 0
    }

    private func select(_ page: Int) {
        guard cards.indices.contains(page) else { return }
        withAnimation(reduceMotion ? nil : .smooth) {
            selection = cards[page].id
        }
    }
}

/// One card face: tap → CARD_SETTINGS (the card's actions as a list); touch and hold → large preview + MENU_CARD_ACTIONS.
private struct CardCarouselItem: View {
    let card: Card
    let content: CardFaceContent
    let isDefault: Bool
    let onOpen: () -> Void
    let onAction: (CardAction) -> Void

    var body: some View {
        Button(action: onOpen) {
            CardFaceView(design: card.design, content: content)
                .cardFaceElevation()
        }
        .buttonStyle(.plain)
        .contentShape(.contextMenuPreview, CardFaceShape())
        .contextMenu {
            CardActionsMenu(hasLink: card.url != nil, isDefault: isDefault, isReadOnly: card.isReadOnly, perform: onAction)
        } preview: {
            CardFaceView(design: card.design, content: content)
                .frame(width: 340)
        }
        .accessibilityLabel(Text("\(card.name) Card"))
        .accessibilityValue(isDefault ? Text("Default") : Text(""))
        .accessibilityHint("Opens card settings. Touch and hold for card actions.")
    }
}
