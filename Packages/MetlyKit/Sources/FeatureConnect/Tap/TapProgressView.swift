import SwiftUI

/// "Connecting with {first}…" after the phones touched.
struct TapProgressView: View {
    let person: NearbyPerson
    let detail: String
    var onCancel: (() -> Void)?
    @ScaledMetric(relativeTo: .largeTitle) private var avatarSize: CGFloat = 72

    var body: some View {
        VStack(spacing: 14) {
            PersonAvatar(name: person.fullName, url: person.avatarURL, size: avatarSize)
            VStack(spacing: 4) {
                Text(ConnectCopy.connectingWith(person.firstName))
                    .font(.title3.bold())
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            ProgressView()
            if let onCancel {
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel Request to \(person.firstName)")
            }
        }
    }
}
