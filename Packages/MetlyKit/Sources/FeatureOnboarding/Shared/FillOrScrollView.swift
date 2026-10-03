import SwiftUI

/// Fills the screen when the content fits (so `Spacer`s can push buttons to the bottom),
/// and falls back to a vertical `ScrollView` when Dynamic Type makes it taller than the screen.
struct FillOrScrollView<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .vertical) {
            content
            ScrollView {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}
