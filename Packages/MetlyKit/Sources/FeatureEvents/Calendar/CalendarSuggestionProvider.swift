import EventKit
import Foundation
import Observation

/// "From Your Calendar" (START_EVENT): full calendar access, requested in context (PLAN Q16), and
/// today's / upcoming events as `CalendarSuggestion`s. Creating it is cheap — EventKit is touched only
/// by `refresh()` / `requestAccess()`. Previews use `init(preview:suggestions:)`.
@Observable
final class CalendarSuggestionProvider {
    enum Access: Equatable, Sendable {
        case notDetermined
        case granted
        /// Denied, or write-only (reading needs full access) — fixable in Settings.
        case denied
        /// Parental controls / MDM — the user can't change it.
        case restricted
    }

    private(set) var access: Access
    private(set) var suggestions: [CalendarSuggestion]
    private(set) var isRequesting = false

    /// How far ahead suggestions reach.
    static let lookAheadDays = 14
    static let maxSuggestions = 6

    @ObservationIgnored private var store: EKEventStore?
    @ObservationIgnored private let isPreview: Bool

    init() {
        isPreview = false
        access = Self.currentAccess()
        suggestions = []
    }

    init(preview access: Access, suggestions: [CalendarSuggestion] = []) {
        isPreview = true
        self.access = access
        self.suggestions = access == .granted ? suggestions : []
    }

    /// Re-reads the authorization (e.g. back from Settings) and, with full access, the upcoming events.
    func refresh(now: Date = .now, calendar: Calendar = .current) {
        guard !isPreview else { return }
        access = Self.currentAccess()
        guard access == .granted else {
            suggestions = []
            return
        }
        suggestions = Self.upcoming(in: eventStore, now: now, calendar: calendar)
    }

    /// Shows the system prompt (first time only), then refreshes.
    func requestAccess() async {
        guard !isPreview, access == .notDetermined, !isRequesting else { return }
        isRequesting = true
        defer { isRequesting = false }
        _ = try? await eventStore.requestFullAccessToEvents()
        refresh()
    }

    private var eventStore: EKEventStore {
        if let store { return store }
        let store = EKEventStore()
        self.store = store
        return store
    }

    private static func currentAccess() -> Access {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .restricted: .restricted
        default: .denied
        }
    }

    /// Events overlapping today … +14 days that haven't finished, excluding birthdays; soonest first.
    private static func upcoming(in store: EKEventStore, now: Date, calendar: Calendar) -> [CalendarSuggestion] {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: lookAheadDays, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        let events = store.events(matching: predicate)
            .filter { $0.endDate > now && $0.calendar?.type != .birthday }
            .sorted { $0.startDate < $1.startDate }

        var seen = Set<String>()
        var suggestions: [CalendarSuggestion] = []
        for event in events {
            let title = (event.title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, let identifier = event.eventIdentifier else { continue }
            let suggestion = CalendarSuggestion(eventIdentifier: identifier, title: title,
                                                location: event.structuredLocation?.title ?? event.location ?? "",
                                                startDate: event.startDate, endDate: event.endDate,
                                                isAllDay: event.isAllDay, calendar: calendar)
            guard seen.insert(suggestion.id).inserted else { continue }
            suggestions.append(suggestion)
            if suggestions.count == maxSuggestions { break }
        }
        return suggestions
    }
}
