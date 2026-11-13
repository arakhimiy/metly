import MetlyDesign
import SwiftUI

/// PEOPLE empty: "No Connections Yet" with Open Connect / Show My QR.
struct PeopleEmptyState: View {
    let canShowQR: Bool
    let onConnect: () -> Void
    let onShowQR: () -> Void

    var body: some View {
        EmptyStateView(.connections, title: "No Connections Yet",
                       message: "Scan someone’s card or open Connect. Your notes about them stay private.") {
            Button("Open Connect", systemImage: "person.badge.plus", action: onConnect)
                .prominentButtonStyle()
            if canShowQR {
                Button("Show My QR", systemImage: "qrcode", action: onShowQR)
                    .secondaryButtonStyle()
            }
        }
    }
}

/// PEOPLE loading: five redacted rows.
struct PeopleSkeletonList: View {
    var body: some View {
        List {
            Section {
                ForEach(0..<5, id: \.self) { _ in
                    PersonRowPlaceholder()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading people")
    }
}
