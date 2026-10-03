import SwiftUI

// Liquid Glass on iOS 26+, system materials on iOS 18–25. Never hand-roll blur.

public extension View {
    /// Floating chrome (HUDs, overlay buttons, banners).
    @ViewBuilder
    func glassOrMaterial<S: Shape>(in shape: S, interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            self.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            self.background(.regularMaterial, in: shape)
        }
    }

    /// Prominent call-to-action button style (glass prominent on iOS 26, bordered prominent before).
    @ViewBuilder
    func prominentButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent)
        }
    }

    /// Secondary button style (glass on iOS 26, bordered before).
    @ViewBuilder
    func secondaryButtonStyle() -> some View {
        if #available(iOS 26, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }
}
