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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var avatarSize: CGFloat = 44

    /// The button keeps one place at the right of every row, so a list of people lines up; name and
    /// role wrap instead. "Waiting…" sits under the name, leaving only Cancel on the right. Only
    /// accessibility sizes put the button under the name.
    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    identity
                    trailing
                }
            } else {
                HStack(spacing: 12) {
                    identity
                        .layoutPriority(1)
                    Spacer(minLength: 8)
                    trailing
                        .fixedSize()
                }
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
                    .lineLimit(2)
                if !person.role.isEmpty {
                    Text(person.role)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if status == .waiting {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Waiting…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConnectCopy.waitingAccessibility(person.firstName))
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
            Button("Cancel", role: .cancel, action: onCancel)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Cancel Request to \(person.firstName)")
        }
    }
}
