import Foundation
import MetlyCapture
import MetlyCore
import MetlyData

/// The editable values of REMINDER_EDIT (SPEC §2.5.34).
struct ReminderForm: Equatable {
    var personID: UUID?
    /// "To Do" — empty means "Follow up".
    var title: String
    /// The reminder's calendar day (time part ignored).
    var day: Date
    /// The reminder's hour and minute (day part ignored).
    var time: Date
    var channel: FollowUpChannel

    /// New reminder: tomorrow at 10:00.
    static func new(personID: UUID?, channel: FollowUpChannel, now: Date = .now, calendar: Calendar = .current) -> ReminderForm {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let time = calendar.date(bySettingHour: MetlyCapture.defaultFollowUpHour, minute: 0, second: 0, of: today) ?? now
        return ReminderForm(personID: personID, title: "", day: tomorrow, time: time, channel: channel)
    }

    static func editing(title: String, dueAt: Date, channel: FollowUpChannel, personID: UUID?,
                        calendar: Calendar = .current) -> ReminderForm {
        let isDefaultTitle = title == MetlyCapture.defaultFollowUpTitle
        return ReminderForm(personID: personID, title: isDefaultTitle ? "" : title,
                            day: calendar.startOfDay(for: dueAt), time: dueAt, channel: channel)
    }

    func dueDate(calendar: Calendar = .current) -> Date {
        FollowUpDates.combine(day: day, time: time, calendar: calendar)
    }

    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? MetlyCapture.defaultFollowUpTitle : trimmed
    }

    var canSave: Bool { personID != nil }

    /// Earliest selectable day: today, or the reminder's own earlier day when editing an overdue one.
    static func minimumDay(existingDue: Date?, now: Date = .now, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        guard let existingDue else { return today }
        return min(today, calendar.startOfDay(for: existingDue))
    }

    /// Footer: "Tanishly will remind you tomorrow at 10:00." / "… on Tue, Sep 29 at 10:00."
    func summary(now: Date = .now, calendar: Calendar = .current, locale: Locale = .autoupdatingCurrent) -> String {
        let due = dueDate(calendar: calendar)
        guard due > now else {
            return String(localized: "This time has already passed. Pick a later time to be reminded.")
        }
        let time = FollowUpDates.time(due, calendar: calendar, locale: locale)
        let app = Brand.appName
        switch FollowUpDates.dayOffset(from: now, to: due, calendar: calendar) {
        case 0: return String(localized: "\(app) will remind you today at \(time).")
        case 1: return String(localized: "\(app) will remind you tomorrow at \(time).")
        default:
            let day = FollowUpDates.shortDay(due, calendar: calendar, locale: locale)
            return String(localized: "\(app) will remind you on \(day) at \(time).")
        }
    }
}
