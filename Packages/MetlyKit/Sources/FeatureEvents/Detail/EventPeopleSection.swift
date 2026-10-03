import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// "People You Met" — rows open CONNECTION_DETAIL; an empty state while nobody is tagged yet.
struct EventPeopleSection: View {
    let people: [Connection]
    let isActive: Bool
    /// Whether the event has a card whose QR code can be shown.
    let canShowQR: Bool
    let onShowQR: () -> Void
    let onJustMet: () -> Void

    var body: some View {
        Section {
            if people.isEmpty {
                EventPeopleEmptyState(isActive: isActive, canShowQR: canShowQR, onShowQR: onShowQR, onJustMet: onJustMet)
            } else {
                ForEach(people) { person in
                    NavigationLink(value: PushDestination.connectionDetail(id: person.id)) {
                        EventPersonRow(person: person)
                    }
                }
            }
        } header: {
            Text("People You Met")
        }
    }
}

/// Compact empty state for a list row (ContentUnavailableView stretches inside a List).
/// Each button keeps its own style so the row never fires both.
private struct EventPeopleEmptyState: View {
    let isActive: Bool
    let canShowQR: Bool
    let onShowQR: () -> Void
    let onJustMet: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            VStack(spacing: 4) {
                Text(isActive ? "No One Yet" : "No One Added")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(isActive
                     ? "People you connect with while this event is active are added here automatically."
                     : "Nobody was added to this event.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            if isActive {
                VStack(spacing: 8) {
                    if canShowQR {
                        Button("Show QR Code", systemImage: "qrcode", action: onShowQR)
                            .prominentButtonStyle()
                    }
                    Button("Who Did You Just Meet?", action: onJustMet)
                        .buttonStyle(.bordered)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
