import Foundation
import MetlyCore
import MetlyData
import SwiftData

/// Starting, editing, ending and resuming events (SPEC §3.17).
///
/// The app calls `endExpiredEvents(in:)` on launch and whenever it returns to the foreground
/// (or attaches `.endsExpiredEvents()` to the main tab view, which also shows EVENT_ENDED).
public enum EventLifecycle {
    /// True once the event's last day is over (local calendar) — "it ends by itself after the last day".
    public static func isExpired(_ event: Event, now: Date = .now, calendar: Calendar = .current) -> Bool {
        now >= endOfLastDay(event, calendar: calendar)
    }

    /// Ends every active event whose last day is over and saves. Returns the ended events' ids
    /// (oldest first) so the caller can show EVENT_ENDED for them.
    @discardableResult
    public static func endExpiredEvents(in modelContext: ModelContext, now: Date = .now,
                                        calendar: Calendar = .current) -> [UUID] {
        let active = (try? modelContext.fetch(Event.active)) ?? []
        let expired = active.filter { isExpired($0, now: now, calendar: calendar) }
        guard !expired.isEmpty else { return [] }
        for event in expired {
            end(event, at: min(endOfLastDay(event, calendar: calendar), now))
        }
        try? modelContext.save()
        return expired.map(\.id)
    }

    // MARK: Internal helpers

    /// The moment the event's last day ends (start of the following day).
    static func endOfLastDay(_ event: Event, calendar: Calendar = .current) -> Date {
        let lastDay = calendar.startOfDay(for: max(event.startDate, event.endDate))
        return calendar.date(byAdding: .day, value: 1, to: lastDay) ?? lastDay
    }

    /// Manual or automatic end. Does not save.
    static func end(_ event: Event, at date: Date = .now) {
        event.status = .ended
        event.endedAt = date
        event.markChanged()
    }

    /// "Resume Event": active again; an event whose last day is over runs until the end of today. Does not save.
    static func resume(_ event: Event, now: Date = .now, calendar: Calendar = .current) {
        event.status = .active
        event.endedAt = nil
        if isExpired(event, now: now, calendar: calendar) {
            let today = calendar.startOfDay(for: now)
            event.endDate = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: today) ?? now
        }
        event.markChanged()
    }

    /// Active events, optionally ignoring one (the event being resumed).
    static func activeEvents(in modelContext: ModelContext, excluding id: UUID? = nil) -> [Event] {
        let active = (try? modelContext.fetch(Event.active)) ?? []
        return active.filter { $0.id != id }
    }

    /// Free plan: one active event (`PlanLimits.maxActiveEvents`). Pro: unlimited.
    static func canActivate(in modelContext: ModelContext, limits: PlanLimits, excluding id: UUID? = nil) -> Bool {
        limits.allows(count: activeEvents(in: modelContext, excluding: id).count, of: \.maxActiveEvents)
    }

    /// Saves START_EVENT edits. A rename (and place change) cascades to the event's connections
    /// whose stamped values still match the old ones (SPEC §2.5.30 "edit renames the event on all its connections").
    static func update(_ event: Event, with draft: EventDraft, in modelContext: ModelContext,
                       calendar: Calendar = .current) {
        let people = (try? modelContext.fetch(Connection.live)) ?? []
        let members = EventMembership.members(of: event, among: people)
        let old = (name: event.name.trimmed, place: event.place.trimmed, city: event.city.trimmed)
        draft.write(to: event, calendar: calendar)
        let new = (name: event.name, place: event.place, city: event.city)

        for person in members {
            var context = person.context
            context.eventID = event.id
            context.eventName = new.name
            if (context.place ?? "").trimmed == old.place { context.place = new.place.isEmpty ? nil : new.place }
            if (context.city ?? "").trimmed == old.city { context.city = new.city.isEmpty ? nil : new.city }
            let linkChanged = person.event?.id != event.id
            if context != person.context || linkChanged {
                person.context = context
                if linkChanged { person.event = event }
                person.markChanged()
            }
        }
        // "Earlier Meetings" at this event, on anyone (they may have been met again elsewhere since).
        for person in people {
            renameEarlierMeetings(of: person, eventID: event.id, to: new.name)
        }
        try? modelContext.save()
    }

    private static func renameEarlierMeetings(of person: Connection, eventID: UUID, to name: String) {
        guard person.previousMeetings.contains(where: { $0.eventID == eventID && $0.eventName != name }) else { return }
        person.previousMeetings = person.previousMeetings.map { meeting in
            guard meeting.eventID == eventID else { return meeting }
            var renamed = meeting
            renamed.eventName = name
            return renamed
        }
        person.markChanged()
    }
}
