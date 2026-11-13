import Foundation

/// MENU_SNOOZE: Tomorrow · In 3 Days · Next Week · Custom… (SPEC §2.6, §9 Q14).
/// Swipe Snooze and the notification's "Snooze 1 Day" use `.tomorrow` (+1 day).
nonisolated enum SnoozeOption: String, CaseIterable, Identifiable, Sendable {
    case tomorrow, inThreeDays, nextWeek, custom

    var id: String { rawValue }

    /// Days added to the base day; nil for Custom… (opens REMINDER_EDIT).
    var days: Int? {
        switch self {
        case .tomorrow: 1
        case .inThreeDays: 3
        case .nextWeek: 7
        case .custom: nil
        }
    }

    /// Menu title. When the reminder is due in the future the base is its own day, so
    /// "Tomorrow" would be misleading — the menu then says "1 Day Later" etc.
    func title(relativeToToday: Bool) -> String {
        switch (self, relativeToToday) {
        case (.tomorrow, true): String(localized: "Tomorrow", bundle: .appStrings)
        case (.inThreeDays, true): String(localized: "In 3 Days", bundle: .appStrings)
        case (.nextWeek, true): String(localized: "Next Week", bundle: .appStrings)
        case (.tomorrow, false): String(localized: "1 Day Later", bundle: .appStrings)
        case (.inThreeDays, false): String(localized: "3 Days Later", bundle: .appStrings)
        case (.nextWeek, false): String(localized: "1 Week Later", bundle: .appStrings)
        case (.custom, _): String(localized: "Custom…", bundle: .appStrings)
        }
    }

    var systemImage: String {
        switch self {
        case .tomorrow: "sunrise"
        case .inThreeDays: "calendar"
        case .nextWeek: "calendar.badge.clock"
        case .custom: "calendar.badge.plus"
        }
    }

    /// Whether snoozing counts from today (the reminder is due today or overdue).
    static func isRelativeToToday(dueAt: Date, now: Date, calendar: Calendar) -> Bool {
        FollowUpDates.dayOffset(from: now, to: dueAt, calendar: calendar) <= 0
    }

    /// New due date: base day = max(due day, today), plus `days`, keeping the reminder's time of day.
    static func snoozedDate(_ dueAt: Date, byDays days: Int, now: Date, calendar: Calendar) -> Date {
        let base = max(calendar.startOfDay(for: dueAt), calendar.startOfDay(for: now))
        let day = calendar.date(byAdding: .day, value: days, to: base) ?? base
        return FollowUpDates.combine(day: day, time: dueAt, calendar: calendar)
    }

    /// The new due date for this option (nil for Custom…).
    func snoozedDate(from dueAt: Date, now: Date, calendar: Calendar) -> Date? {
        days.map { Self.snoozedDate(dueAt, byDays: $0, now: now, calendar: calendar) }
    }
}
