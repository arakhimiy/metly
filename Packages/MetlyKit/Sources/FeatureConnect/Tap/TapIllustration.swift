import SwiftUI

/// Two iPhones held top to top, gently bumping (static with Reduce Motion).
struct TapIllustration: View {
    var isAnimating: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let phases: [Bool] = isAnimating && !reduceMotion ? [false, true] : [false]
        PhaseAnimator(phases) { together in
            // Offsets, not spacing: the illustration keeps its size, so the text under it stays put.
            VStack(spacing: 2) {
                Image(systemName: "iphone.gen3")
                    .rotationEffect(.degrees(180))
                    .offset(y: together ? 0 : -6)
                Image(systemName: "iphone.gen3")
                    .offset(y: together ? 0 : 6)
            }
            .padding(.vertical, 6)
            .overlay {
                Image(systemName: "wave.3.up")
                    .font(.footnote.weight(.bold))
                    .opacity(together ? 1 : 0)
            }
        } animation: { together in
            together ? .spring(duration: 0.3, bounce: 0.45) : .easeInOut(duration: 1.1)
        }
        .font(.largeTitle)
        .imageScale(.large)
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    }
}
