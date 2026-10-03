import Foundation
import MetlyData

/// Name and subtitle text for people shown in follow-up rows and pickers.
nonisolated enum PersonText {
    /// "Kamila Yusupova" → "Kamila".
    static func firstName(_ fullName: String) -> String {
        let trimmed = fullName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.split(separator: " ").first.map(String.init) ?? trimmed
    }

    /// Name for a reminder whose person is missing.
    static func displayName(_ person: Connection?) -> String {
        let name = person?.fullName.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? String(localized: "Someone") : name
    }

    /// "{event or company}" — the second part of "{name} · {event or company}".
    static func context(of person: Connection?) -> String? {
        guard let person else { return nil }
        let candidates = [person.context.eventName, person.company, person.context.place]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }

    /// "{event} · {city}" for Recent rows (falls back to place / company).
    static func meetingMeta(of person: Connection) -> String {
        let context = person.context
        let whereMet = [context.eventName, context.place, person.company]
            .compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        let city = context.city?.trimmingCharacters(in: .whitespaces)
        return [whereMet, city].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Case- and diacritic-insensitive search over name, company, title and event.
    static func matches(_ person: Connection, query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [person.fullName, person.company, person.jobTitle, person.context.eventName ?? ""]
            .contains { $0.localizedStandardContains(query) }
    }
}
