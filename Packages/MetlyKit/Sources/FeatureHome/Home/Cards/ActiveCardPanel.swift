import MetlyCore
import MetlyData
import MetlyDesign
import MetlySharedUI
import SwiftUI

/// The active card's name, stats ("Viewed 14 · Saved 9 · Shared back 5"), "…" menu and the
/// two CTAs under the carousel: Show QR (prominent) and Share.
struct ActiveCardPanel: View {
    let card: Card
    let isDefault: Bool
    let onAction: (CardAction) -> Void
    let onShowQR: () -> Void
    let onShare: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(card.name)
                            .font(.headline)
                        if isDefault {
                            Text("Default")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(.tint)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.tint.opacity(0.12), in: .capsule)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    if let stats = CardStatsText(stats: card.stats) {
                        stats
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    CardActionsMenu(hasLink: card.url != nil, isDefault: isDefault, isReadOnly: card.isReadOnly, perform: onAction)
                } label: {
                    Label("Card Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                        .font(.title2)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(.rect)
                }
                .accessibilityLabel(Text("Actions for \(card.name) Card"))
            }

            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Button(action: onShowQR) {
                    Label("Show QR", systemImage: "qrcode")
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .secondaryButtonStyle()
            }
            .controlSize(.large)
            .font(.body.weight(.semibold))
        }
        .padding(.vertical, 4)
    }
}

/// "Viewed 14 · Saved 9 · Shared back 5" — nil while every count is zero (Q30: per card, all time).
struct CardStatsText: View {
    let stats: CardStats

    init?(stats: CardStats) {
        guard stats.views > 0 || stats.saves > 0 || stats.shareBacks > 0 else { return nil }
        self.stats = stats
    }

    var body: some View {
        Text("Viewed \(stats.views) · Saved \(stats.saves) · Shared back \(stats.shareBacks)")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("Viewed \(stats.views) times, saved \(stats.saves) times, shared back \(stats.shareBacks) times"))
    }
}
