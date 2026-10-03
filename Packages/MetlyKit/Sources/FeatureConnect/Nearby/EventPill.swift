import SwiftUI

/// "Event pill if active" (SPEC §2.5.26): new connections are tagged with the active event.
struct EventPill: View {
    let name: String

    var body: some View {
        Label(name, systemImage: "calendar")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.tint)
            .lineLimit(2)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.tint.opacity(0.12), in: .capsule)
            .accessibilityLabel("Event: \(name)")
            .accessibilityHint("New connections are added to this event")
    }
}
