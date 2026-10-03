import Foundation
import MetlyCore
import MetlyData
import SwiftData

public extension CaptureDraft {
    /// Commits the draft (SPEC §3.14 commit rules) and saves the context.
    ///
    /// - Where You Met: replaces `connection.context` and links the `Event` record while its name is unchanged.
    ///   With `.newMeeting`, the previous meeting moves to `previousMeetings` when the event differs.
    /// - Note / tags: replaced (`.editContext`) or appended / merged (`.newMeeting`).
    /// - Follow-up: moves the person's open reminder (others are removed), or creates one if the plan allows.
    ///   A blocked follow-up never blocks the rest of the save — check `result.hitFollowUpLimit`.
    ///
    /// `connection` must already be inserted into `modelContext`.
    @discardableResult
    func apply(to connection: Connection, in modelContext: ModelContext, limits: PlanLimits,
               now: Date = .now, calendar: Calendar = .current) -> CaptureResult {
        applyContext(to: connection, in: modelContext)
        applyNote(to: connection)

        var outcome = CaptureResult.FollowUpOutcome.none
        if let followUp {
            outcome = FollowUpPolicy.commit(followUp, to: connection, in: modelContext,
                                            limits: limits, now: now, calendar: calendar)
        }

        connection.markChanged()
        try? modelContext.save()
        return CaptureResult(followUp: outcome)
    }

    private func applyContext(to connection: Connection, in modelContext: ModelContext) {
        var meeting = meetingContext
        // Keep the Event link only while the typed name still matches that event.
        var linkedEvent: Event?
        if let id = meeting.eventID, let event = modelContext.record(Event.self, id: id), !event.isDeleted,
           event.name.trimmed.caseInsensitiveCompare(meeting.eventName ?? "") == .orderedSame {
            linkedEvent = event
        } else {
            meeting.eventID = nil
        }

        if intent == .newMeeting, Self.isDifferentMeeting(connection.context, meeting) {
            connection.previousMeetings.insert(connection.context, at: 0)
        }
        connection.context = meeting
        connection.event = linkedEvent
    }

    private func applyNote(to connection: Connection) {
        let newNote = note.trimmed
        let cleanTags = Self.normalized(tags)
        switch intent {
        case .editContext:
            connection.note = newNote
            connection.tags = cleanTags
        case .newMeeting:
            if !newNote.isEmpty {
                connection.note = connection.note.trimmed.isEmpty ? newNote : connection.note + "\n\n" + newNote
            }
            connection.tags = Self.normalized(connection.tags + cleanTags)
        }
    }

    /// Whether `new` is another meeting than `old` (the previous one then belongs in "Earlier Meetings"):
    /// `old` had an event or place and the event name changed.
    static func isDifferentMeeting(_ old: MeetingContext, _ new: MeetingContext) -> Bool {
        let oldEvent = (old.eventName ?? "").trimmed
        let oldPlace = (old.place ?? "").trimmed
        guard !oldEvent.isEmpty || !oldPlace.isEmpty else { return false }
        return oldEvent.caseInsensitiveCompare((new.eventName ?? "").trimmed) != .orderedSame
    }

    /// Trimmed, non-empty, de-duplicated (case-insensitive) tags in their original order.
    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let clean = tag.trimmed
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { return nil }
            return clean
        }
    }
}
