import SwiftUI

/// "Nearby on Metly" row: avatar, name, "{title} · {company}", Connect → Waiting… (SPEC §2.5.26).
struct NearbyPersonRow: View {
    enum Status: Equatable {
        case ready(canConnect: Bool)
        case waiting
    }

    let person: NearbyPerson
    let status: Status
    let onConnect: () -> Void
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 44

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        layout {
            identity
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
            }
            trailing
        }
        .padding(.vertical, 4)
    }

    private var identity: some View {
        HStack(spacing: 12) {
            PersonAvatar(name: person.fullName, url: person.avatarURL, size: avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.fullName)
                    .font(.headline)
                if !person.role.isEmpty {
                    Text(person.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        switch status {
        case .ready(let canConnect):
            Button("Connect", action: onConnect)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .disabled(!canConnect)
                .accessibilityLabel("Connect with \(person.firstName)")
                .accessibilityHint("Sends your card and asks for theirs")
        case .waiting:
            HStack(spacing: 10) {
                ProgressView()
                Text("Waiting…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .cancel, action: onCancel)
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel Request to \(person.firstName)")
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ConnectCopy.waitingAccessibility(person.firstName))
        }
    }
}
