import SwiftUI

/// The three stat tiles — People · With Notes · Follow-ups (EVENT_DETAIL, EVENT_ENDED).
/// Stacks vertically at accessibility text sizes.
struct EventStatsRow: View {
    let stats: EventStats

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            EventStatTile(value: stats.people, title: "People")
            EventStatTile(value: stats.withNotes, title: "With Notes")
            EventStatTile(value: stats.openFollowUps, title: "Follow-ups")
        }
        .padding(.vertical, 4)
    }
}

/// A big number over a caption.
struct EventStatTile: View {
    let value: Int
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value, format: .number)
                .font(.title2.bold())
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(value)))
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
