import MetlyCardKit
import MetlyDesign
import SwiftUI

/// Page 1 — two overlapping sample cards with a QR badge.
struct ShareCardHero: View {
    let isActive: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            CardFaceView(design: OnboardingSamples.personalDesign, content: OnboardingSamples.ownerCard)
                .rotationEffect(.degrees(-9))
                .offset(x: -20, y: -26)
                .shadow(color: .black.opacity(0.12), radius: 10, y: 6)

            CardFaceView(design: OnboardingSamples.workDesign, content: OnboardingSamples.ownerCard)
                .rotationEffect(.degrees(4))
                .offset(x: 14, y: 22)
                .shadow(color: .black.opacity(0.22), radius: 16, y: 10)
        }
        .containerRelativeFrame(.horizontal) { length, _ in min(length * 0.66, 320) }
        .padding(.vertical, 28)
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "qrcode.viewfinder")
                .font(.title)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tint)
                .padding(14)
                .glassOrMaterial(in: .circle)
                .symbolEffect(.bounce, value: isActive)
                .symbolEffectsRemoved(reduceMotion)
                .offset(x: 8, y: -4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Two sample business cards with a QR code")
        .accessibilityAddTraits(.isImage)
    }
}
