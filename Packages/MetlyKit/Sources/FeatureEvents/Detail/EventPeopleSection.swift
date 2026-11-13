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

/// "Nobody yet" inside the section. While the event runs, the ways to meet someone; afterwards, just the fact.
private struct EventPeopleEmptyState: View {
    let isActive: Bool
    let canShowQR: Bool
    let onShowQR: () -> Void
    let onJustMet: () -> Void

    var body: some View {
        if isActive {
            EmptyStateView(.events, title: "No One Yet",
                           message: "People you connect with while this event is active are added here automatically.",
                           style: .inline) {
                // Each button keeps its own style so the row never fires both.
                if canShowQR {
                    Button("Show QR Code", systemImage: "qrcode", action: onShowQR)
                        .subtleButtonStyle()
                }
                Button("Who Did You Just Meet?", systemImage: "person.badge.plus", action: onJustMet)
                    .subtleButtonStyle()
            }
        } else {
            EmptyStateView(.events, title: "No One Added", message: "Nobody was added to this event.", style: .inline) {
                EmptyView()
            }
        }
    }
}
