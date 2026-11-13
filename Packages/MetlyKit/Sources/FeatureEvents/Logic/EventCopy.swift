import Foundation
import MetlyData
import MetlyCapture

/// User-facing strings built from event data (SPEC §2.5.15, §2.5.31, §7.2).
enum EventCopy {
    /// "Sep 24 – 26", "Sep 24" for a single day; the year is added outside the current year.
    static func dateRange(start: Date, end: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let lower = min(start, end)
        let upper = max(start, end)
        let thisYear = calendar.isDate(lower, equalTo: now, toGranularity: .year)
            && calendar.isDate(upper, equalTo: now, toGranularity: .year)
        if calendar.isDate(lower, inSameDayAs: upper) {
            let day = Date.FormatStyle.dateTime.month(.abbreviated).day()
            return lower.formatted(thisYear ? day : day.year())
        }
        let interval = Date.IntervalFormatStyle.interval.month(.abbreviated).day()
        return (lower..<upper).formatted(thisYear ? interval : interval.year())
    }

    static func dateRange(of event: Event, now: Date = .now) -> String {
        dateRange(start: event.startDate, end: event.endDate, now: now)
    }

    /// "Hyatt Regency, Tashkent" (empty when neither is known).
    static func place(of event: Event) -> String {
        PlaceText.joined(place: event.place, city: event.city) ?? ""
    }

    /// EVENT_ENDED: "You met 6 people. 2 have notes. 4 follow-ups are scheduled."
    static func summary(_ stats: EventStats) -> String {
        guard stats.people > 0 else { return String(localized: "You didn’t add anyone at this event.", bundle: .appStrings) }
        let people = stats.people == 1 ? String(localized: "You met 1 person.", bundle: .appStrings) : String(localized: "You met \(stats.people) people.", bundle: .appStrings)
        let notes = switch stats.withNotes {
        case 0: String(localized: "None have notes yet.", bundle: .appStrings)
        case 1: String(localized: "1 has a note.", bundle: .appStrings)
        default: String(localized: "\(stats.withNotes) have notes.", bundle: .appStrings)
        }
        let followUps = switch stats.openFollowUps {
        case 0: String(localized: "No follow-ups are scheduled.", bundle: .appStrings)
        case 1: String(localized: "1 follow-up is scheduled.", bundle: .appStrings)
        default: String(localized: "\(stats.openFollowUps) follow-ups are scheduled.", bundle: .appStrings)
        }
        return "\(people) \(notes) \(followUps)"
    }

    /// Toast after "Follow Up with Everyone": "4 reminders set for tomorrow".
    static func remindersSet(_ count: Int) -> String {
        count == 1 ? String(localized: "1 reminder set for tomorrow", bundle: .appStrings) : String(localized: "\(count) reminders set for tomorrow", bundle: .appStrings)
    }

    /// "Follow Up with Everyone I Haven’t Yet (3)".
    static func followUpEveryone(_ count: Int) -> String {
        String(localized: "Follow Up with Everyone Else (\(count))", bundle: .appStrings)
    }
}
