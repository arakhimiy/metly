import Foundation
import MetlyCore
import MetlyData
import MetlyCapture

/// One person in the export, as plain display values (no CSV escaping yet).
struct EventCSVRow: Identifiable, Equatable, Sendable {
    let id: UUID
    private var values: [EventCSVColumn: String]

    init(id: UUID = UUID(), values: [EventCSVColumn: String]) {
        self.id = id
        self.values = values
    }

    subscript(column: EventCSVColumn) -> String {
        values[column] ?? ""
    }

    /// Builds the row for a connection met at `eventName`.
    init(person: Connection, eventName: String, calendar: Calendar = .current) {
        let context = person.context
        let place = PlaceText.joined(context) ?? ""
        self.init(id: person.id, values: [
            .name: person.fullName,
            .jobTitle: person.jobTitle,
            .company: person.company,
            .phone: person.phone,
            .email: person.email,
            .telegram: person.telegram,
            .website: person.website,
            .linkedin: person.linkedin,
            .event: eventName.trimmed,
            .metAt: Self.timestamp(context.metAt, calendar: calendar),
            .place: place,
            .note: person.note.trimmed,
            .tags: person.tags.joined(separator: ", "),
            .followUp: Self.followUpText(for: person, calendar: calendar),
        ])
    }

    /// "Send the pitch deck · 2026-09-27 10:00 · Telegram"; "Done" when every reminder is done; "" when none.
    static func followUpText(for person: Connection, calendar: Calendar = .current) -> String {
        if let open = person.openFollowUp {
            return "\(open.title) · \(timestamp(open.dueAt, calendar: calendar)) · \(open.channel.title)"
        }
        return person.followUps.contains { $0.isDone && !$0.isDeleted } ? "Done" : ""
    }

    /// Spreadsheet-friendly local timestamp: "2026-09-24 14:32".
    static func timestamp(_ date: Date, calendar: Calendar = .current) -> String {
        let style = Date.VerbatimFormatStyle(
            format: "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
            locale: Locale(identifier: "en_US_POSIX"),
            timeZone: calendar.timeZone,
            calendar: calendar)
        return date.formatted(style)
    }
}
