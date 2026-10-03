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
                .fixedSize(horizontal: false, vertical: true)
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                let status = Text("In Progress").fontWeight(.semibold).foregroundStyle(.green)
                Text("\(status) · new connections are added automatically")
                    .foregroundStyle(.secondary)
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
