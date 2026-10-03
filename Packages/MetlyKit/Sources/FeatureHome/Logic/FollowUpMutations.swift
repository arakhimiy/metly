import Foundation
import MetlyData
import SwiftData

/// Reminder mutations behind Done / Snooze / Delete. Each is a soft change (`markChanged` / `markDeleted`)
/// that saves the context — the save also triggers notification rescheduling — and returns its Undo.
enum FollowUpMutations {
    typealias Undo = @MainActor () -> Void

    @discardableResult
    static func markDone(_ followUp: FollowUp, in context: ModelContext, now: Date = .now) -> Undo {
        setDone(true, on: followUp, in: context, now: now)
        return { setDone(false, on: followUp, in: context, now: now) }
    }

    /// "Moved Back" — reopens a done reminder.
    @discardableResult
    static func reopen(_ followUp: FollowUp, in context: ModelContext, now: Date = .now) -> Undo {
        setDone(false, on: followUp, in: context, now: now)
        return { setDone(true, on: followUp, in: context, now: now) }
    }

    /// Moves the reminder to `newDate` and returns an Undo that restores the old due date.
    @discardableResult
    static func reschedule(_ followUp: FollowUp, to newDate: Date, in context: ModelContext) -> Undo {
        let previous = followUp.dueAt
        followUp.dueAt = newDate
        followUp.markChanged()
        try? context.save()
        return {
            followUp.dueAt = previous
            followUp.markChanged()
            try? context.save()
        }
    }

    @discardableResult
    static func delete(_ followUp: FollowUp, in context: ModelContext) -> Undo {
        followUp.markDeleted()
        try? context.save()
        return {
            followUp.restore()
            try? context.save()
        }
    }

    private static func setDone(_ isDone: Bool, on followUp: FollowUp, in context: ModelContext, now: Date) {
        followUp.isDone = isDone
        followUp.completedAt = isDone ? now : nil
        followUp.markChanged()
        try? context.save()
    }
}
