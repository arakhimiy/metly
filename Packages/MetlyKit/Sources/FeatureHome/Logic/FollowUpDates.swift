import Foundation

/// Calendar-aware date helpers for reminders. Every function takes `now` and a `calendar`
/// so tests can pin "today" (SPEC prototype today: Sat, Sep 26, 2026).
nonisolated enum FollowUpDates {
    /// Whole calendar days from `now`'s day to `date`'s day (negative = in the past).
    static func dayOffset(from now: Date, to date: Date, calendar: Calendar) -> Int {
        let start = calendar.startOfDay(for: now)
        let end = calendar.startOfDay(for: date)
        return calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }

    /// The first moment of the calendar day after `date` — when "Today" / "Overdue" labels roll over.
    /// Calendar arithmetic, so 23- and 25-hour DST days still roll over at midnight.
    static func startOfNextDay(after date: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    }

    /// Due label (SPEC §2.5.14): "Today", "Tomorrow", "Yesterday", else "Tue, Sep 29".
    static func dueLabel(_ due: Date, now: Date = .now, calendar: Calendar = .current,
                         locale: Locale = .autoupdatingCurrent) -> String {
        switch dayOffset(from: now, to: due, calendar: calendar) {
        case 0: String(localized: "Today")
        case 1: String(localized: "Tomorrow")
        case -1: String(localized: "Yesterday")
        default: shortDay(due, calendar: calendar, locale: locale)
        }
    }

    /// "Tue, Sep 29".
    static func shortDay(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        date.formatted(dayStyle(calendar: calendar, locale: locale))
    }

    /// "10:00" / "10:00 AM" in the user's locale.
    static func time(_ date: Date, calendar: Calendar, locale: Locale = .autoupdatingCurrent) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return date.formatted(style)
    }

    /// `day`'s calendar date at `time`'s hour and minute.
    static func combine(day: Date, time: Date, calendar: Calendar) -> Date {
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: clock.hour ?? 10, minute: clock.minute ?? 0, second: 0,
                             of: calendar.startOfDay(for: day)) ?? day
    }

    private static func dayStyle(calendar: Calendar, locale: Locale) -> Date.FormatStyle {
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar)
        style.timeZone = calendar.timeZone
        return style.weekday(.abbreviated).month(.abbreviated).day()
    }
}
