import SwiftUI

extension View {
    /// Pins a primary action under scrolling content: a scroll-edge bar on iOS 26 (Liquid Glass),
    /// the system bar material before.
    @ViewBuilder
    func bottomActionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom) { content() }
        } else {
            safeAreaInset(edge: .bottom) { content().background(.bar) }
        }
    }
}
