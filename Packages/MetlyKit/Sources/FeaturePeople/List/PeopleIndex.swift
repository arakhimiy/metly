import Foundation
import MetlyCore
import MetlyData

/// A titled group of people (Places → city, Tags → tag).
struct PeopleGroup: Identifiable {
    let id: String
    let title: String
    let people: [Connection]
}

/// An event card on the Events filter.
struct EventSummary: Identifiable {
    /// Event record id, or "name:<lowercased name>" for events only known from connections.
    let id: String
    let eventID: UUID?
    let name: String
    let place: String
    let startDate: Date
    let endDate: Date
    let isActive: Bool
    let people: [Connection]

    var notesCount: Int { people.count { !$0.note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    var followUpsCount: Int { people.count { $0.openFollowUp != nil } }
}

/// Search, sort and grouping for the People tab (pure functions over live connections).
enum PeopleIndex {
    static let otherPlacesTitle = "Other"
    static let untaggedTitle = "No Tags"

    /// Most recent meeting first.
    static func sorted(_ people: [Connection]) -> [Connection] {
        people.sorted { lhs, rhs in
            if lhs.context.metAt != rhs.context.metAt { return lhs.context.metAt > rhs.context.metAt }
            return lhs.createdAt > rhs.createdAt
        }
    }

    /// Matches name, company, title, event, place, city and tags.
    static func search(_ people: [Connection], query: String) -> [Connection] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return people }
        return people.filter { person in
            searchableFields(of: person).contains { $0.localizedStandardContains(query) }
        }
    }

    static func searchableFields(of person: Connection) -> [String] {
        [person.fullName, person.company, person.jobTitle,
         person.context.eventName ?? "", person.context.place ?? "", person.context.city ?? ""] + person.tags
    }

    /// Places: one group per city (most recent first); people without a city go to "Other" at the end.
    static func groupedByCity(_ people: [Connection]) -> [PeopleGroup] {
        var buckets: [String: (title: String, people: [Connection])] = [:]
        for person in sorted(people) {
            let city = (person.context.city ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let key = city.isEmpty ? "" : city.lowercased()
            buckets[key, default: (city.isEmpty ? otherPlacesTitle : city, [])].people.append(person)
        }
        return buckets
            .map { PeopleGroup(id: "city:" + $0.key, title: $0.value.title, people: $0.value.people) }
            .sorted { lhs, rhs in
                if lhs.id == "city:" { return false }
                if rhs.id == "city:" { return true }
                return (lhs.people.first?.context.metAt ?? .distantPast) > (rhs.people.first?.context.metAt ?? .distantPast)
            }
    }

    /// Tags: one group per tag (a person appears under each of their tags), biggest first; untagged last.
    static func groupedByTag(_ people: [Connection]) -> [PeopleGroup] {
        var buckets: [String: (title: String, people: [Connection])] = [:]
        var untagged: [Connection] = []
        for person in sorted(people) {
            let tags = person.tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if tags.isEmpty { untagged.append(person) }
            for tag in Set(tags.map { $0.lowercased() }) {
                let title = tags.first { $0.lowercased() == tag } ?? tag
                buckets[tag, default: (title, [])].people.append(person)
            }
        }
        var groups = buckets
            .map { PeopleGroup(id: "tag:" + $0.key, title: $0.value.title, people: $0.value.people) }
            .sorted { lhs, rhs in
                if lhs.people.count != rhs.people.count { return lhs.people.count > rhs.people.count }
                return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
        if !untagged.isEmpty {
            groups.append(PeopleGroup(id: "tag:", title: untaggedTitle, people: untagged))
        }
        return groups
    }

    /// Events: every event record that has people (plus the active event, even when empty) and events only
    /// known by name from connections. Active first, then most recent. With a query, only events whose
    /// name matches or that contain a matching person.
    static func eventSummaries(people: [Connection], events: [Event], query: String = "") -> [EventSummary] {
        let live = sorted(people)
        var claimed = Set<UUID>()
        var summaries: [EventSummary] = []

        for event in events where !event.isDeleted {
            let name = event.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let members = live.filter { person in
                person.event?.id == event.id || person.context.eventID == event.id
                    || (person.context.eventID == nil && person.event == nil
                        && (person.context.eventName ?? "").caseInsensitiveCompare(name) == .orderedSame)
            }
            guard !members.isEmpty || event.isActive else { continue }
            members.forEach { claimed.insert($0.id) }
            let place = [event.place, event.city].filter { !$0.isEmpty }.joined(separator: ", ")
            summaries.append(EventSummary(id: event.id.uuidString, eventID: event.id, name: event.name, place: place,
                                          startDate: min(event.startDate, event.endDate),
                                          endDate: max(event.startDate, event.endDate),
                                          isActive: event.isActive, people: members))
        }

        var derived: [String: [Connection]] = [:]
        for person in live where !claimed.contains(person.id) {
            let name = (person.context.eventName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            derived[name.lowercased(), default: []].append(person)
        }
        for (key, members) in derived {
            let dates = members.map(\.context.metAt)
            let first = members[0]
            let place = [first.context.place, first.context.city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
            summaries.append(EventSummary(id: "name:" + key, eventID: nil, name: first.context.eventName ?? key,
                                          place: place, startDate: dates.min() ?? .now, endDate: dates.max() ?? .now,
                                          isActive: false, people: members))
        }

        let filtered: [EventSummary]
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            filtered = summaries
        } else {
            filtered = summaries.compactMap { summary in
                if summary.name.localizedStandardContains(trimmedQuery) { return summary }
                let matching = search(summary.people, query: trimmedQuery)
                guard !matching.isEmpty else { return nil }
                return EventSummary(id: summary.id, eventID: summary.eventID, name: summary.name, place: summary.place,
                                    startDate: summary.startDate, endDate: summary.endDate,
                                    isActive: summary.isActive, people: matching)
            }
        }

        return filtered.sorted { lhs, rhs in
            if lhs.isActive != rhs.isActive { return lhs.isActive }
            return lhs.endDate > rhs.endDate
        }
    }
}
