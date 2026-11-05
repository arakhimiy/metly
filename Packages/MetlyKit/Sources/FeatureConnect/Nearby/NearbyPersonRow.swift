import SwiftUI

/// "Nearby on Tanishly" row: avatar, name, "{title} · {company}", Connect → Waiting… (SPEC §2.5.26).
struct NearbyPersonRow: View {
    enum Status: Equatable {
        case ready(canConnect: Bool)
        case waiting
    }

    let person: NearbyPerson
    let status: Status
    let onConnect: () -> Void
    let onCancel: () -> Void

    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 44

    /// One line when the name and the button fit side by side; otherwise the button goes under the
    /// name (large text, long names, "Waiting… Cancel") instead of squeezing both.
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                identity
                Spacer(minLength: 8)
                trailing
            }
            VStack(alignment: .leading, spacing: 12) {
                identity
                trailing
            }
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
