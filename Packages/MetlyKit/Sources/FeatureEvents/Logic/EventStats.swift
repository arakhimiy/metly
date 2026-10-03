import Foundation
import MetlyData

/// Derived event numbers (SPEC §4.2 "derived stats"): People · With notes · Follow-ups.
struct EventStats: Equatable, Sendable {
    /// People met at the event.
    var people: Int
    /// People with a private note.
    var withNotes: Int
    /// Open (not done, not deleted) reminders for those people.
    var openFollowUps: Int
    /// People without an open reminder — the "Follow Up with Everyone I Haven't Yet ({N})" count.
    var withoutFollowUp: Int

    init(people: Int = 0, withNotes: Int = 0, openFollowUps: Int = 0, withoutFollowUp: Int = 0) {
        self.people = people
        self.withNotes = withNotes
        self.openFollowUps = openFollowUps
        self.withoutFollowUp = withoutFollowUp
    }

    /// `members` should come from `EventMembership.members(of:among:)`.
    init(members: [Connection]) {
        var withNotes = 0
        var openFollowUps = 0
        var withoutFollowUp = 0
        for person in members {
            if !person.note.trimmed.isEmpty { withNotes += 1 }
            let open = person.followUps.count { !$0.isDone && !$0.isDeleted }
            openFollowUps += open
            if open == 0 { withoutFollowUp += 1 }
        }
        self.init(people: members.count, withNotes: withNotes, openFollowUps: openFollowUps,
                  withoutFollowUp: withoutFollowUp)
    }
}
