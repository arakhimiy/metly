import Foundation

/// Due label + emphasis for follow-up rows (SPEC §2.5.14): "Today", "Tomorrow", "Yesterday",
/// else "Tue, Sep 29"; red when overdue, tinted today.
nonisolated public struct WidgetDueLabel: Hashable, Sendable {
    public enum Emphasis: Hashable, Sendable { case overdue, today, upcoming }

    public let text: String
    public let emphasis: Emphasis

    public init(due: Date, now: Date, calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) {
        let start = calendar.startOfDay(for: now)
        let offset = calendar.dateComponents([.day], from: start, to: calendar.startOfDay(for: due)).day ?? 0
        switch offset {
        case 0: text = String(localized: "Today")
        case 1: text = String(localized: "Tomorrow")
        case -1: text = String(localized: "Yesterday")
        default:
            var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: locale, calendar: calendar)
            style.timeZone = calendar.timeZone
            text = due.formatted(style.weekday(.abbreviated).month(.abbreviated).day())
        }
        emphasis = offset < 0 ? .overdue : (offset == 0 ? .today : .upcoming)
    }

    /// Spoken after the label ("Yesterday, overdue").
    public var accessibilityNote: String? {
        emphasis == .overdue ? String(localized: "Overdue") : nil
    }
}

/// When widget timelines need a fresh entry: now, then every midnight for two days
/// ("due today" and "this week" roll over at midnight).
nonisolated public enum WidgetTimelineSchedule {
    public static func entryDates(from now: Date, calendar: Calendar = .current, days: Int = 2) -> [Date] {
        var dates = [now]
        var next = now
        for _ in 0..<max(days, 0) {
            next = WidgetSnapshot.startOfNextDay(after: next, calendar: calendar)
            dates.append(next)
        }
        return dates
    }
}
