import Foundation
import MetlyData
import SwiftData

/// Which connections belong to an event — the same rules as People › Events:
/// linked to the `Event` record (relationship or stamped id), or — for older records without
/// a link — stamped with the same event name.
enum EventMembership {
    static func isMember(_ person: Connection, of event: Event) -> Bool {
        if person.event?.id == event.id || person.context.eventID == event.id { return true }
        guard person.event == nil, person.context.eventID == nil else { return false }
        let name = event.name.trimmed
        let stamped = (person.context.eventName ?? "").trimmed
        guard !name.isEmpty, !stamped.isEmpty else { return false }
        return stamped.caseInsensitiveCompare(name) == .orderedSame
    }

    /// Live, unblocked members, most recently met first.
    static func members(of event: Event, among people: [Connection]) -> [Connection] {
        people
            .filter { !$0.isDeleted && !$0.isBlocked && isMember($0, of: event) }
            .sorted { $0.context.metAt > $1.context.metAt }
    }

    static func members(of event: Event, in modelContext: ModelContext) -> [Connection] {
        members(of: event, among: (try? modelContext.fetch(Connection.live)) ?? [])
    }

    /// Members without a private note yet (the "No Note Yet" list).
    static func withoutNotes(_ members: [Connection]) -> [Connection] {
        members.filter { $0.note.trimmed.isEmpty }
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
