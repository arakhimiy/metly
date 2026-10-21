import Foundation

/// Follow-up quick picks shown as chips: Tomorrow · In 3 Days · Next Week · Pick a Date…
public enum FollowUpQuickPick: String, CaseIterable, Identifiable, Sendable {
    case tomorrow
    case inThreeDays
    case nextWeek
    case custom

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tomorrow: "Tomorrow"
        case .inThreeDays: "In 3 Days"
        case .nextWeek: "Next Week"
        case .custom: "Pick a Date…"
        }
    }

    /// Days from today, nil for `.custom`.
    public var dayOffset: Int? {
        switch self {
        case .tomorrow: 1
        case .inThreeDays: 3
        case .nextWeek: 7
        case .custom: nil
        }
    }

    /// Due date for this pick: the target day (custom dates are never before today) at the hour/minute of `time`
    /// in local time. Never in the past: "today" at a time that has already passed moves to tomorrow.
    public func dueDate(customDate: Date, time: Date, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let day: Date
        if let dayOffset {
            day = calendar.date(byAdding: .day, value: dayOffset, to: today) ?? today
        } else {
            day = max(calendar.startOfDay(for: customDate), today)
        }
        let clock = calendar.dateComponents([.hour, .minute], from: time)
        let due = Self.date(on: day, hour: clock.hour, minute: clock.minute, calendar: calendar)
        guard due <= now, let nextDay = calendar.date(byAdding: .day, value: 1, to: day) else { return due }
        return Self.date(on: nextDay, hour: clock.hour, minute: clock.minute, calendar: calendar)
    }

    private static func date(on day: Date, hour: Int?, minute: Int?, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour ?? MetlyCapture.defaultFollowUpHour, minute: minute ?? 0, second: 0, of: day) ?? day
    }

    /// The quick pick whose day matches `due` (to highlight an existing reminder); `.custom` otherwise.
    public static func matching(_ due: Date, now: Date = .now, calendar: Calendar = .current) -> FollowUpQuickPick {
        let today = calendar.startOfDay(for: now)
        let dueDay = calendar.startOfDay(for: due)
        let days = calendar.dateComponents([.day], from: today, to: dueDay).day
        return allCases.first { $0.dayOffset != nil && $0.dayOffset == days } ?? .custom
    }

    /// Today at the default reminder time (10:00 local) — the default for the Time picker.
    public static func defaultTime(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: MetlyCapture.defaultFollowUpHour, minute: 0, second: 0, of: now) ?? now
    }

    /// Default date for "Pick a Date…": today + 5 days (SPEC §3.14).
    public static func defaultCustomDate(now: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 5, to: calendar.startOfDay(for: now)) ?? now
    }
}
