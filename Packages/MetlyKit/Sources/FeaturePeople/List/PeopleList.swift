import MetlyCore
import MetlyData
import SwiftUI

/// The People list: filter, Requests and the filtered groups.
struct PeopleList: View {
    let connections: [Connection]
    let requests: [ConnectRequest]
    let events: [Event]
    let query: String
    @Binding var filter: PeopleFilter
    let sharedCardName: String?
    let onAccept: (ConnectRequest) -> Void
    let onDecline: (ConnectRequest) -> Void
    let rowActions: PersonRowActions

    var body: some View {
        let matches = PeopleIndex.search(connections, query: query)
        let summaries = filter == .events
            ? PeopleIndex.eventSummaries(people: connections, events: events, query: query) : []
        List {
            Section {
                Picker("Filter", selection: $filter) {
                    ForEach(PeopleFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            if !requests.isEmpty {
                RequestsSection(requests: requests, sharedCardName: sharedCardName,
                                onAccept: onAccept, onDecline: onDecline)
            }

            switch filter {
            case .all:
                AllPeopleSection(people: PeopleIndex.sorted(matches), actions: rowActions)
            case .events:
                EventsSection(summaries: summaries)
            case .places:
                GroupedPeopleSections(groups: PeopleIndex.groupedByCity(matches), meta: .eventAndDate, actions: rowActions)
            case .tags:
                GroupedPeopleSections(groups: PeopleIndex.groupedByTag(matches), meta: .event, actions: rowActions)
            }
        }
        .animation(.default, value: filter)
        .overlay {
            if filter == .events && summaries.isEmpty {
                if query.isEmpty {
                    ContentUnavailableView("No Events Yet", systemImage: "calendar",
                                           description: Text("Start an event from Home. Everyone you meet there is grouped together."))
                } else {
                    ContentUnavailableView.search
                }
            } else if filter != .events && !query.isEmpty && matches.isEmpty {
                ContentUnavailableView.search
            }
        }
    }
}

private struct RequestsSection: View {
    let requests: [ConnectRequest]
    let sharedCardName: String?
    let onAccept: (ConnectRequest) -> Void
    let onDecline: (ConnectRequest) -> Void

    var body: some View {
        Section {
            ForEach(requests) { request in
                RequestRow(request: request, onAccept: { onAccept(request) }, onDecline: { onDecline(request) })
            }
        } header: {
            Text("Requests")
        } footer: {
            if let sharedCardName {
                Text("Accepting shares your \(sharedCardName) card.")
            }
        }
    }
}

private struct AllPeopleSection: View {
    let people: [Connection]
    let actions: PersonRowActions

    var body: some View {
        if !people.isEmpty {
            Section {
                ForEach(people) { person in
                    PersonListRow(person: person, meta: .event, actions: actions)
                }
            } header: {
                HStack {
                    Text("All People")
                    Spacer()
                    Text(people.count, format: .number)
                }
            } footer: {
                Text("Swipe left or touch and hold a person for more actions.")
            }
        }
    }
}

private struct GroupedPeopleSections: View {
    let groups: [PeopleGroup]
    let meta: PersonRowMeta
    let actions: PersonRowActions

    var body: some View {
        ForEach(groups) { group in
            Section {
                ForEach(group.people) { person in
                    PersonListRow(person: person, meta: meta, actions: actions)
                }
            } header: {
                HStack {
                    Text(group.title)
                    Spacer()
                    Text(group.people.count, format: .number)
                }
            }
        }
    }
}

private struct EventsSection: View {
    let summaries: [EventSummary]

    var body: some View {
        if !summaries.isEmpty {
            Section("Events") {
                ForEach(summaries) { summary in
                    if let eventID = summary.eventID {
                        NavigationLink(value: PushDestination.eventDetail(id: eventID)) {
                            EventSummaryRow(summary: summary)
                        }
                    } else {
                        EventSummaryRow(summary: summary)
                    }
                }
            }
        }
    }
}
