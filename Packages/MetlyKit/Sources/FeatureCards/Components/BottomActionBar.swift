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
            HStack(spacing: 12) {
                secondary.frame(maxWidth: .infinity)
                primary.frame(maxWidth: .infinity)
            }
            VStack(spacing: 10) {
                primary.frame(maxWidth: .infinity)
                secondary.frame(maxWidth: .infinity)
            }
        }
        .controlSize(.large)
    }
}
