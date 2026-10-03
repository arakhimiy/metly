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

private struct EventPeopleEmptyState: View {
    let isActive: Bool
    let canShowQR: Bool
    let onShowQR: () -> Void
    let onJustMet: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(isActive ? "No One Yet" : "No One Added", systemImage: "person.2")
        } description: {
            Text(isActive
                 ? "People you connect with while this event is active are added here automatically."
                 : "Nobody was added to this event.")
        } actions: {
            if isActive {
                if canShowQR {
                    Button("Show QR Code", systemImage: "qrcode", action: onShowQR)
                        .prominentButtonStyle()
                }
                Button("Who Did You Just Meet?", action: onJustMet)
            }
        }
    }
}
