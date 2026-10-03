import SwiftUI

public extension View {
    /// Hairline edge + soft shadow so a card face stays visible on any background
    /// (e.g. a light Snow card on a light grouped background). Apply to a `CardFaceView`.
    func cardFaceElevation() -> some View {
        modifier(CardFaceElevation())
    }
}

struct CardFaceElevation: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .overlay {
                CardFaceShape().strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.18 : 0.12), lineWidth: 0.5)
            }
            .background {
                // Shadow cast by a backing shape, not the face itself (which would shadow every glyph).
                CardFaceShape()
                    .fill(.background)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.10),
                            radius: colorScheme == .dark ? 14 : 10, y: 6)
            }
    }
}
