import SwiftUI

extension View {
    /// Pins actions to the bottom edge above scrolling content: a safe-area bar with the system
    /// scroll-edge effect on iOS 26, a bar-material inset before.
    @ViewBuilder
    func bottomActionBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
        if #available(iOS 26, *) {
            safeAreaBar(edge: .bottom) { bar() }
        } else {
            safeAreaInset(edge: .bottom) {
                bar().background(.bar)
            }
        }
    }
}
