import MetlyData
import SwiftUI

/// Dates, place and status ("In Progress · new connections are added automatically" / "Ended …").
struct EventHeaderSection: View {
    let event: Event

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Label(EventCopy.dateRange(of: event), systemImage: "calendar")
                    let place = EventCopy.place(of: event)
                    if !place.isEmpty {
                        Label(place, systemImage: "mappin.and.ellipse")
                    }
                }
                EventStatusLine(event: event)
            }
            .padding(.vertical, 4)
        }
    }
}

private struct EventStatusLine: View {
    let event: Event

    var body: some View {
        if event.isActive {
            Label {
                let status = Text("In Progress").fontWeight(.semibold).foregroundStyle(.green)
                Text("\(status) · new connections are added automatically")
                    .foregroundStyle(.secondary)
            } icon: {
                Image(systemName: "circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }
            .font(.subheadline)
        } else {
            Label(endedText, systemImage: "flag.checkered")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var endedText: String {
        guard let endedAt = event.endedAt else { return "Ended" }
        return "Ended \(endedAt.formatted(.dateTime.month(.abbreviated).day()))"
    }
}
