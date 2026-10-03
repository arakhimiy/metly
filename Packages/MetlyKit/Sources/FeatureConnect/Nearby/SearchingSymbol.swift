import SwiftUI

/// Animated "looking for people" glyph. The variable-color sweep stops with Reduce Motion.
struct SearchingSymbol: View {
    var isSearching: Bool
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: "dot.radiowaves.left.and.right")
            .font(.largeTitle)
            .imageScale(.large)
            .foregroundStyle(.tint)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isSearching && !reduceMotion)
            .frame(width: diameter, height: diameter)
            .background(.tint.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}
