import Foundation
import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData

/// What saving REMINDER_EDIT did.
nonisolated enum ReminderSaveResult: Equatable, Sendable {
    case created(id: UUID)
    case updated(id: UUID)
    /// Free plan: 5 open reminders already (ALERT_FU_LIMIT).
    case limitReached(openCount: Int)
    /// "Choose a person first".
    case missingPerson
}

/// Commits REMINDER_EDIT. Unlike capture flows, the editor may add a second open reminder for the
/// same person (PLAN Q13) — but every new one counts toward the Free limit.
enum ReminderEditor {
    static func save(_ form: ReminderForm, existing: FollowUp?, in context: ModelContext,
                     limits: PlanLimits, calendar: Calendar = .current) -> ReminderSaveResult {
        let due = form.dueDate(calendar: calendar)

        if let existing {
            existing.title = form.resolvedTitle
            existing.dueAt = due
            existing.channel = form.channel
            existing.markChanged()
            try? context.save()
            return .updated(id: existing.id)
        }

        guard let personID = form.personID, let person = context.record(Connection.self, id: personID) else {
            return .missingPerson
        }
        let openCount = FollowUpPolicy.openCount(in: context)
        guard limits.allows(count: openCount, of: \.maxOpenFollowUps) else {
            return .limitReached(openCount: openCount)
        }
        let reminder = FollowUp(title: form.resolvedTitle, channel: form.channel, dueAt: due)
        context.insert(reminder)
        reminder.connection = person
        try? context.save()
        return .created(id: reminder.id)
    }
}
