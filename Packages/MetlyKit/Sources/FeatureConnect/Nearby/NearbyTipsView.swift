import SwiftUI

/// Tips under "No One Nearby Yet".
struct NearbyTipsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(ConnectCopy.emptyTips, id: \.self) { tip in
                Label {
                    Text(tip)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tips. \(ConnectCopy.emptyTips.joined(separator: " "))")
    }
}
