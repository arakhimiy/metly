import MetlyCardKit
import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftUI

/// "Order" (only with more than one card): every card in Home order — drag in Edit mode, or use
/// Move Up / Move Down for this card. Footer "Order on Home."
struct CardOrderSection: View {
    let currentID: UUID
    /// Live cards in Home order.
    let cards: [Card]
    let profile: Profile?
    let onReorder: ([UUID]) -> Void

    var body: some View {
        Section {
            ForEach(cards) { card in
                CardOrderRow(card: card, content: CardContentFactory.preview(of: card, profile: profile),
                             isCurrent: card.id == currentID)
                    .accessibilityActions {
                        if canMove(card.id, by: -1) {
                            Button("Move Up") { move(card.id, by: -1) }
                        }
                        if canMove(card.id, by: 1) {
                            Button("Move Down") { move(card.id, by: 1) }
                        }
                    }
            }
            .onMove(perform: moveRows)

            Button("Move Up", systemImage: "arrow.up") { move(currentID, by: -1) }
                .disabled(!canMove(currentID, by: -1))
            Button("Move Down", systemImage: "arrow.down") { move(currentID, by: 1) }
                .disabled(!canMove(currentID, by: 1))
        } header: {
            Text("Order")
        } footer: {
            Text("Order on Home. Tap Edit to drag cards into a new order.")
        }
    }

    private var ids: [UUID] { cards.map(\.id) }

    private func canMove(_ id: UUID, by step: Int) -> Bool {
        CardOrdering.moving(id, by: step, in: ids) != nil
    }

    private func move(_ id: UUID, by step: Int) {
        guard let order = CardOrdering.moving(id, by: step, in: ids) else { return }
        onReorder(order)
    }

    private func moveRows(from offsets: IndexSet, to destination: Int) {
        onReorder(CardOrdering.moving(ids, fromOffsets: offsets, toOffset: destination))
    }
}

/// Mini card + name; "This Card" marks the one being edited.
struct CardOrderRow: View {
    let card: Card
    let content: CardFaceContent
    let isCurrent: Bool
    @ScaledMetric(relativeTo: .body) private var thumbnailWidth: CGFloat = 56

    var body: some View {
        HStack(spacing: 12) {
            CardFaceView(design: card.design, content: content)
                .frame(width: thumbnailWidth)
                .overlay {
                    CardFaceShape().strokeBorder(Color(.separator), lineWidth: 0.5)
                }
                .accessibilityHidden(true)
            Text(card.name)
            Spacer(minLength: 8)
            if isCurrent {
                Text("This Card")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
