import MetlyCore
import MetlyDesign
import SwiftUI

/// Event card on the Events filter: name, "In Progress", place · dates, face pile and counts.
struct EventSummaryRow: View {
    let summary: EventSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(summary.name)
                    .font(.headline)
                Spacer(minLength: 8)
                if summary.isActive {
                    InProgressBadge()
                }
            }
            Text(placeAndDates)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                if !summary.people.isEmpty {
                    FacePile(names: summary.people.prefix(4).map(\.fullName))
                }
                Text("^[\(summary.people.count) person](inflect: true) · ^[\(summary.notesCount) note](inflect: true) · ^[\(summary.followUpsCount) follow-up](inflect: true)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var placeAndDates: String {
        let dates = (summary.startDate..<max(summary.endDate, summary.startDate.addingTimeInterval(1)))
            .formatted(.interval.month(.abbreviated).day())
        return summary.place.isEmpty ? dates : "\(summary.place) · \(dates)"
    }
}

private struct InProgressBadge: View {
    var body: some View {
        Label {
            Text("In Progress")
        } icon: {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.green)
    }
}

/// Up to four overlapping initials avatars.
struct FacePile: View {
    let names: [String]

    var body: some View {
        HStack(spacing: -8) {
            ForEach(names.indices, id: \.self) { index in
                InitialsAvatar(name: names[index], size: 28)
                    .overlay {
                        Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}
