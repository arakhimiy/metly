import SwiftUI

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
