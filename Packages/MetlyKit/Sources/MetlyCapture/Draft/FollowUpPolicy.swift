import Foundation
import MetlyCore
import MetlyData
import SwiftData

/// Follow-up rules shared by every surface (PLAN "Resolved open questions" Q13):
/// • Free plan: at most `PlanLimits.maxOpenFollowUps` (5) open reminders, enforced everywhere.
/// • Capture flows keep **one open reminder per person**: picking a day moves the existing one.
public enum FollowUpPolicy {
    /// Open (not done, not deleted) reminders whose person hasn't been removed — the number the limit counts.
    public static func openCount(in modelContext: ModelContext) -> Int {
        let open = (try? modelContext.fetch(FollowUp.open)) ?? []
        return open.count { $0.connection?.isDeleted != true }
    }

    /// Whether picking a day is allowed. Rescheduling an existing reminder never counts against the limit.
    public static func canSchedule(hasOpenReminder: Bool, in modelContext: ModelContext, limits: PlanLimits) -> Bool {
        hasOpenReminder || limits.allows(count: openCount(in: modelContext), of: \.maxOpenFollowUps)
    }

    /// Reply channel by available fields: Telegram, else Email, else Call (Telegram when nothing is known).
    public static func preferredChannel(phone: String, email: String, telegram: String) -> FollowUpChannel {
        if !telegram.trimmed.isEmpty { return .telegram }
        if !email.trimmed.isEmpty { return .email }
        if !phone.trimmed.isEmpty { return .call }
        return .telegram
    }

    public static func preferredChannel(for connection: Connection?) -> FollowUpChannel {
        guard let connection else { return .telegram }
        return preferredChannel(phone: connection.phone, email: connection.email, telegram: connection.telegram)
    }

    /// One-tap "Tap a day to reschedule" (CONNECTION_DETAIL chips, Home): moves the person's open reminder,
    /// or creates one ("Follow up", preferred channel, 10:00) when the plan allows. Saves the context.
    @discardableResult
    public static func schedule(_ pick: FollowUpQuickPick, for connection: Connection, in modelContext: ModelContext,
                                limits: PlanLimits, now: Date = .now, calendar: Calendar = .current) -> CaptureResult {
        var draft = FollowUpDraft(pick: pick, channel: connection.openFollowUp?.channel ?? preferredChannel(for: connection),
                                  now: now, calendar: calendar)
        if let open = connection.openFollowUp {
            draft.time = open.dueAt
        }
        let outcome = commit(draft, to: connection, in: modelContext, limits: limits, now: now, calendar: calendar)
        try? modelContext.save()
        return CaptureResult(followUp: outcome)
    }

    /// Applies a follow-up draft to `connection` (must already be inserted). Does not save.
    static func commit(_ draft: FollowUpDraft, to connection: Connection, in modelContext: ModelContext,
                       limits: PlanLimits, now: Date, calendar: Calendar) -> CaptureResult.FollowUpOutcome {
        let due = draft.dueDate(now: now, calendar: calendar)
        let open = connection.followUps
            .filter { !$0.isDone && !$0.isDeleted }
            .sorted { $0.dueAt < $1.dueAt }

        if let existing = open.first {
            existing.dueAt = due
            existing.channel = draft.channel
            if let title = draft.trimmedTitle { existing.title = title }
            existing.markChanged()
            for extra in open.dropFirst() { extra.markDeleted() }
            return .rescheduled(id: existing.id)
        }

        let count = openCount(in: modelContext)
        guard limits.allows(count: count, of: \.maxOpenFollowUps) else {
            return .limitReached(openCount: count)
        }
        let reminder = FollowUp(title: draft.trimmedTitle ?? MetlyCapture.defaultFollowUpTitle,
                                channel: draft.channel, dueAt: due)
        modelContext.insert(reminder)
        reminder.connection = connection
        return .scheduled(id: reminder.id)
    }
}
