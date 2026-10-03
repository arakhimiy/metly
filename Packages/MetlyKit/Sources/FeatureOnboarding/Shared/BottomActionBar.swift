import SwiftUI

extension View {
    /// Pins primary actions to the bottom edge, within thumb reach.
    /// iOS 26: `safeAreaBar` (system scroll-edge effect, Liquid Glass buttons float on content).
    /// iOS 18–25: `safeAreaInset` over the system bar material.
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        modifier(BottomActionBarModifier(bar: bar()))
    }
}

private struct BottomActionBarModifier<Bar: View>: ViewModifier {
    let bar: Bar

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .bottom) {
                padded
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                padded.background(.bar)
            }
        }
    }

    private var padded: some View {
        bar
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 8)
    }
}
