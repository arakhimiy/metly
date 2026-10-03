import SwiftUI

extension View {
    /// Pins primary actions to the bottom edge: a scroll-edge-aware bar on iOS 26,
    /// a bar-material inset before.
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(BottomActionBarModifier(bar: bar()))
    }
}

private struct BottomActionBarModifier<Bar: View>: ViewModifier {
    let bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom) {
                bar.padding(.horizontal).padding(.vertical, 8)
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                bar.padding(.horizontal).padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                    .background(.bar)
            }
        }
    }
}

/// One or two full-width buttons that stack vertically at large text sizes.
struct ActionButtonStack<Primary: View, Secondary: View>: View {
    @ViewBuilder let primary: Primary
    @ViewBuilder let secondary: Secondary

    var body: some View {
        ViewThatFits(in: .horizontal) {
            EqualWidthHStack(spacing: 12) {
                secondary
                primary
            }
            VStack(spacing: 10) {
                primary.frame(maxWidth: .infinity)
                secondary.frame(maxWidth: .infinity)
            }
        }
        .controlSize(.large)
    }
}

/// Lays out children side by side with equal widths. Its ideal width is (widest child × count), so
/// inside `ViewThatFits` it is rejected as soon as any label would have to wrap.
struct EqualWidthHStack: Layout {
    var spacing: Double = 12

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified) }
        let totalSpacing = spacing * Double(subviews.count - 1)
        let widest = ideal.map(\.width).max() ?? 0
        let width = proposal.width ?? (widest * Double(subviews.count) + totalSpacing)
        let columnWidth = max((width - totalSpacing) / Double(subviews.count), 0)
        let height = subviews.map { $0.sizeThatFits(ProposedViewSize(width: columnWidth, height: nil)).height }.max() ?? 0
        return CGSize(width: max(width, widest * Double(subviews.count) + totalSpacing), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        guard !subviews.isEmpty else { return }
        let totalSpacing = spacing * Double(subviews.count - 1)
        let columnWidth = max((bounds.width - totalSpacing) / Double(subviews.count), 0)
        var x = bounds.minX
        for subview in subviews {
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: columnWidth, height: bounds.height))
            x += columnWidth + spacing
        }
    }
}
