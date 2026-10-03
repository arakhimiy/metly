import Foundation
import MetlyCore

/// The follow-up part of a capture: which quick pick, the time, what to do and how to reply.
public struct FollowUpDraft: Equatable, Sendable {
    public var pick: FollowUpQuickPick
    /// Only used for `.custom` (min today, default today + 5 days).
    public var customDate: Date
    /// Hour/minute of the reminder (default 10:00).
    public var time: Date
    /// "To Do" — empty means "Follow up" (or keep the existing reminder's title when rescheduling).
    public var title: String
    public var channel: FollowUpChannel

    public init(pick: FollowUpQuickPick, channel: FollowUpChannel, title: String = "",
                now: Date = .now, calendar: Calendar = .current) {
        self.pick = pick
        self.channel = channel
        self.title = title
        self.customDate = FollowUpQuickPick.defaultCustomDate(now: now, calendar: calendar)
        self.time = FollowUpQuickPick.defaultTime(now: now, calendar: calendar)
    }

    public func dueDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        pick.dueDate(customDate: customDate, time: time, now: now, calendar: calendar)
    }

    /// Trimmed title, or nil when the user left it empty.
    public var trimmedTitle: String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Read-only description of a person's current open reminder (shown in edit flows).
public struct ReminderSummary: Equatable, Sendable {
    public var title: String
    public var dueAt: Date
    public var channel: FollowUpChannel

    public init(title: String, dueAt: Date, channel: FollowUpChannel) {
        self.title = title
        self.dueAt = dueAt
        self.channel = channel
    }
}
