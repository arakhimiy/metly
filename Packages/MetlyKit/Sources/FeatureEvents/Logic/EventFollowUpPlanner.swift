import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData

/// What "Follow Up with Everyone I Haven't Yet" did.
struct EventFollowUpOutcome: Equatable, Sendable {
    /// Reminders created.
    var scheduled: Int
    /// People left without a reminder because of the Free plan limit.
    var skipped: Int
    /// Open reminders after the action (for ALERT_FU_LIMIT "You have {n}").
    var openCountAfter: Int

    var hitLimit: Bool { skipped > 0 }
}

/// SPEC §2.5.15: one reminder *"Follow up from {event}"* due tomorrow (10:00) for every person
/// without an open reminder; channel Telegram › Email › Call (`FollowUpPolicy.preferredChannel`).
/// The Free plan limit (`PlanLimits.maxOpenFollowUps`) is respected — PLAN Q13: enforced everywhere.
enum EventFollowUpPlanner {
    static func reminderTitle(for eventName: String) -> String {
        String(localized: "Follow up from \(eventName.trimmed)", bundle: .appStrings)
    }

    /// People without an open reminder, in list order.
    static func candidates(among members: [Connection]) -> [Connection] {
        members.filter { $0.openFollowUp == nil }
    }

    /// How many new reminders the plan still allows (nil = unlimited).
    static func remainingCapacity(openCount: Int, limits: PlanLimits) -> Int? {
        limits.maxOpenFollowUps.map { max(0, $0 - openCount) }
    }

    /// Creates the reminders and saves. `members` comes from `EventMembership.members(of:among:)`.
    @discardableResult
    static func followUpWithEveryone(eventName: String, members: [Connection], in modelContext: ModelContext,
                                     limits: PlanLimits, now: Date = .now,
                                     calendar: Calendar = .current) -> EventFollowUpOutcome {
        let candidates = candidates(among: members)
        let openCount = FollowUpPolicy.openCount(in: modelContext)
        let allowed = remainingCapacity(openCount: openCount, limits: limits) ?? candidates.count
        let chosen = candidates.prefix(allowed)

        let due = FollowUpQuickPick.tomorrow.dueDate(customDate: now,
                                                     time: FollowUpQuickPick.defaultTime(now: now, calendar: calendar),
                                                     now: now, calendar: calendar)
        let title = reminderTitle(for: eventName)
        for person in chosen {
            let reminder = FollowUp(title: title, channel: FollowUpPolicy.preferredChannel(for: person), dueAt: due)
            modelContext.insert(reminder)
            reminder.connection = person
        }
        if !chosen.isEmpty { try? modelContext.save() }
        return EventFollowUpOutcome(scheduled: chosen.count, skipped: candidates.count - chosen.count,
                                    openCountAfter: openCount + chosen.count)
    }
}
