import SwiftUI

/// Animated "looking for people" glyph. The variable-color sweep stops with Reduce Motion.
struct SearchingSymbol: View {
    var isSearching: Bool
    var systemName = "dot.radiowaves.left.and.right"
    @ScaledMetric(relativeTo: .largeTitle) private var diameter: CGFloat = 88
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Image(systemName: systemName)
            .font(.largeTitle)
            .imageScale(.large)
            .foregroundStyle(.tint)
            .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isSearching && !reduceMotion)
            .frame(width: diameter, height: diameter)
            .background(.tint.opacity(0.12), in: .circle)
            .accessibilityHidden(true)
    }
}

/// Hero shown above the Nearby list until someone is found (SPEC §2.5.26 Nearby).
struct SearchingHeader: View {
    var isSearching: Bool

    var body: some View {
        VStack(spacing: 12) {
            SearchingSymbol(isSearching: isSearching)
            Text(ConnectCopy.nearbyTitle)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text(ConnectCopy.nearbyMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// Section header for the live list: a small searching glyph + "Nearby on Metly".
struct NearbySectionHeader: View {
    var isSearching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Label {
            Text(ConnectCopy.nearbySectionTitle)
        } icon: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .symbolEffect(.variableColor.iterative.reversing, options: .repeating, isActive: isSearching && !reduceMotion)
                .foregroundStyle(.tint)
        }
    }
}
