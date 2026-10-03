import MetlyCore
import MetlyData
import SwiftUI

/// Active event banner → EVENT_DETAIL, or "Start Event" → START_EVENT (SPEC §2.5.7).
/// No inline End button (removed in prototype v7). Free's one-active-event rule lives in Events.
struct HomeEventSection: View {
    let event: Event?

    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            if let event {
                NavigationLink(value: PushDestination.eventDetail(id: event.id)) {
                    ActiveEventLabel(event: event)
                }
            } else {
                Button(action: startEvent) {
                    StartEventLabel()
                }
            }
        }
    }

    private func startEvent() {
        router.present(.startEvent(eventID: nil))
    }
}

private struct ActiveEventLabel: View {
    let event: Event

    @ScaledMetric(relativeTo: .headline) private var dotSize = 10

    var body: some View {
        let count = event.connections.count { !$0.isDeleted }
        HStack(spacing: 12) {
            Circle()
                .fill(.green)
                .frame(width: dotSize, height: dotSize)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.name)
                    .font(.headline)
                Group {
                    if event.place.isEmpty {
                        Text("^[\(count) new connection](inflect: true)")
                    } else {
                        Text("\(event.place) · ^[\(count) new connection](inflect: true)")
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Active event, \(event.name)"))
        .accessibilityValue(Text("^[\(count) new connection](inflect: true)"))
    }
}

private struct StartEventLabel: View {
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start Event")
                    .font(.headline)
                Text("Everyone you meet is tagged automatically")
                    .font(.subheadline)
                    .foregroundStyle(Color.secondary) // not the button tint
            }
        } icon: {
            Image(systemName: "calendar.badge.plus")
        }
        .padding(.vertical, 2)
    }
}
