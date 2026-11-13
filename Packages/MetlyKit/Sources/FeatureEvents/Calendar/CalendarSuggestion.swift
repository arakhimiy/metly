import Foundation

/// A calendar event offered under "From Your Calendar" (START_EVENT). A plain value so the
/// form logic and previews never touch EventKit.
struct CalendarSuggestion: Identifiable, Equatable, Sendable {
    /// Unique per occurrence (recurring events share `eventIdentifier`).
    let id: String
    /// `EKEvent.eventIdentifier`, stored on `Event.calendarEventIdentifier`.
    let eventIdentifier: String
    let title: String
    let location: String
    let startDate: Date
    /// A moment on the event's last day (all-day and midnight endings are already pulled back a second).
    let lastDay: Date
    let isAllDay: Bool

    init(eventIdentifier: String, title: String, location: String = "", startDate: Date, endDate: Date,
         isAllDay: Bool = false, calendar: Calendar = .current) {
        self.id = "\(eventIdentifier)|\(startDate.timeIntervalSinceReferenceDate)"
        self.eventIdentifier = eventIdentifier
        self.title = title
        self.location = location
        self.startDate = startDate
        self.isAllDay = isAllDay
        let end = max(endDate, startDate)
        // An event ending exactly at midnight belongs to the previous day.
        let endsAtMidnight = end > startDate && calendar.startOfDay(for: end) == end
        self.lastDay = endsAtMidnight ? end.addingTimeInterval(-1) : end
    }

    /// "Today", "Tomorrow", "Friday", "Oct 12"; "Now" while it is already running.
    func dayLabel(now: Date = .now, calendar: Calendar = .current) -> String {
        if startDate < calendar.startOfDay(for: now) { return String(localized: "Now", bundle: .appStrings) }
        if calendar.isDate(startDate, inSameDayAs: now) { return String(localized: "Today", bundle: .appStrings) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(startDate, inSameDayAs: tomorrow) {
            return String(localized: "Tomorrow", bundle: .appStrings)
        }
        if let week = calendar.date(byAdding: .day, value: 6, to: calendar.startOfDay(for: now)), startDate < week {
            return startDate.formatted(.dateTime.weekday(.wide))
        }
        return startDate.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Second line of the row: "Today · Hyatt Regency, Tashkent".
    func subtitle(now: Date = .now, calendar: Calendar = .current) -> String {
        let place = location.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return [dayLabel(now: now, calendar: calendar), place.trimmed].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
