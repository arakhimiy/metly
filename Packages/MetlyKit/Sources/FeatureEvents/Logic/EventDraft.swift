import Foundation
import MetlyData

/// What START_EVENT edits. A plain value: validated here, written to an `Event` on Save.
struct EventDraft: Equatable, Sendable {
    /// Which rules apply to the dates.
    enum Mode: Equatable, Sendable {
        /// New event: starts today or later.
        case new
        /// Editing a running event: it must still be running today (or auto-end would close it).
        case editActive
        /// Editing an event that already ended: any dates, end ≥ start.
        case editEnded

        var isNew: Bool { self == .new }
    }

    enum Issue: Equatable, Sendable {
        case missingName
        case startInPast
        case endBeforeStart
        case endInPast
    }

    var name: String
    var place: String
    var city: String
    var startDate: Date
    var endDate: Date
    var cardID: UUID?
    var calendarEventIdentifier: String?

    /// A new one-day event today.
    init(cardID: UUID? = nil, now: Date = .now, calendar: Calendar = .current) {
        name = ""
        place = ""
        city = ""
        startDate = calendar.startOfDay(for: now)
        endDate = calendar.startOfDay(for: now)
        self.cardID = cardID
        calendarEventIdentifier = nil
    }

    init(event: Event) {
        name = event.name
        place = event.place
        city = event.city
        startDate = min(event.startDate, event.endDate)
        endDate = max(event.startDate, event.endDate)
        cardID = event.cardID
        calendarEventIdentifier = event.calendarEventIdentifier
    }

    var trimmedName: String { name.trimmed }

    // MARK: Validation

    func issues(mode: Mode, now: Date = .now, calendar: Calendar = .current) -> [Issue] {
        let today = calendar.startOfDay(for: now)
        let startDay = calendar.startOfDay(for: startDate)
        let endDay = calendar.startOfDay(for: endDate)
        var issues: [Issue] = []
        if trimmedName.isEmpty { issues.append(.missingName) }
        if mode == .new, startDay < today { issues.append(.startInPast) }
        if endDay < startDay {
            issues.append(.endBeforeStart)
        } else if mode != .editEnded, endDay < today {
            issues.append(.endInPast)
        }
        return issues
    }

    func isValid(mode: Mode, now: Date = .now, calendar: Calendar = .current) -> Bool {
        issues(mode: mode, now: now, calendar: calendar).isEmpty
    }

    /// Earliest selectable start day: today for new events, otherwise unrestricted.
    static func earliestStart(mode: Mode, now: Date = .now, calendar: Calendar = .current) -> Date {
        mode.isNew ? calendar.startOfDay(for: now) : .distantPast
    }

    /// Earliest selectable end day: the start day, and today while the event runs.
    func earliestEnd(mode: Mode, now: Date = .now, calendar: Calendar = .current) -> Date {
        let startDay = calendar.startOfDay(for: startDate)
        guard mode != .editEnded else { return startDay }
        return max(startDay, calendar.startOfDay(for: now))
    }

    /// Keeps the end on or after the start (called when the start moves).
    mutating func keepEndAfterStart(calendar: Calendar = .current) {
        if calendar.startOfDay(for: endDate) < calendar.startOfDay(for: startDate) {
            endDate = startDate
        }
    }

    /// Number of days the event spans (≥ 1).
    func dayCount(calendar: Calendar = .current) -> Int {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: startDate),
                                           to: calendar.startOfDay(for: endDate)).day ?? 0
        return max(days, 0) + 1
    }

    // MARK: Calendar suggestion

    /// Fills name, place (+ city) and dates from a calendar event. A start before today is clamped to today
    /// (new events never start in the past).
    mutating func apply(_ suggestion: CalendarSuggestion, now: Date = .now, calendar: Calendar = .current) {
        name = suggestion.title
        let location = Self.splitLocation(suggestion.location)
        if !location.place.isEmpty {
            place = location.place
            city = location.city
        }
        let today = calendar.startOfDay(for: now)
        startDate = max(calendar.startOfDay(for: suggestion.startDate), today)
        endDate = max(calendar.startOfDay(for: suggestion.lastDay), startDate)
        calendarEventIdentifier = suggestion.eventIdentifier
    }

    /// "Hyatt Regency, Tashkent" → place + city. Longer addresses keep only the venue (first part);
    /// multi-line locations use the first line.
    static func splitLocation(_ location: String) -> (place: String, city: String) {
        let firstLine = location.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let parts = firstLine.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
        switch parts.count {
        case 0: return ("", "")
        case 2: return (parts[0], parts[1])
        default: return (parts[0], "")
        }
    }

    // MARK: Writing

    /// Dates as stored: the first moment of the first day and the last moment of the last day.
    func normalizedDates(calendar: Calendar = .current) -> (start: Date, end: Date) {
        let start = calendar.startOfDay(for: min(startDate, endDate))
        let lastDay = calendar.startOfDay(for: max(startDate, endDate))
        let end = calendar.date(byAdding: DateComponents(day: 1, second: -1), to: lastDay) ?? lastDay
        return (start, end)
    }

    func makeEvent(calendar: Calendar = .current) -> Event {
        let dates = normalizedDates(calendar: calendar)
        let event = Event(name: trimmedName, place: place.trimmed, city: city.trimmed,
                          startDate: dates.start, endDate: dates.end, cardID: cardID)
        event.calendarEventIdentifier = calendarEventIdentifier
        return event
    }

    /// Writes the fields to `event` (no cascade — see `EventLifecycle.update`).
    func write(to event: Event, calendar: Calendar = .current) {
        let dates = normalizedDates(calendar: calendar)
        event.name = trimmedName
        event.place = place.trimmed
        event.city = city.trimmed
        event.startDate = dates.start
        event.endDate = dates.end
        event.cardID = cardID
        event.calendarEventIdentifier = calendarEventIdentifier
        event.markChanged()
    }
}
