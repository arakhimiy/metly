import SwiftUI

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
