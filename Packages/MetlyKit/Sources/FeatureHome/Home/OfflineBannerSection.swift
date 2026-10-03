import SwiftUI

/// "You're offline. Your QR code still works." (SPEC §2.5.7, §3.21).
struct OfflineBannerSection: View {
    var body: some View {
        Section {
            Label {
                Text("You're offline. Your QR code still works.")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "wifi.slash")
                    .foregroundStyle(.orange)
            }
            .font(.subheadline)
            .accessibilityElement(children: .combine)
        }
    }
}
