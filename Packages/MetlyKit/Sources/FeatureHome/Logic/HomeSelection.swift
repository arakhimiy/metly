import Foundation

/// Which records the Home sections show (SPEC §2.5.7).
nonisolated enum HomeSelection {
    /// "Follow Up Today" shows at most three reminders.
    static let followUpLimit = 3
    /// "Recent" shows the first three connections.
    static let recentLimit = 3

    /// Open reminders due today or earlier (overdue + today), earliest first.
    static func dueToday<Item: FollowUpItem>(_ items: [Item], now: Date, calendar: Calendar) -> [Item] {
        items
            .filter { !$0.isDone && FollowUpDates.dayOffset(from: now, to: $0.dueAt, calendar: calendar) <= 0 }
            .sorted { $0.dueAt < $1.dueAt }
    }

    /// Open reminders due after today ("Nothing due today. {N} coming up.").
    static func upcomingCount<Item: FollowUpItem>(_ items: [Item], now: Date, calendar: Calendar) -> Int {
        items.count { !$0.isDone && FollowUpDates.dayOffset(from: now, to: $0.dueAt, calendar: calendar) > 0 }
    }

    /// Most recently met first (a new meeting with a known person moves them up), newest record on ties.
    static func recent<Person: RecentPersonItem>(_ people: [Person], limit: Int = recentLimit) -> [Person] {
        Array(people.sorted {
            $0.metAt == $1.metAt ? $0.createdAt > $1.createdAt : $0.metAt > $1.metAt
        }.prefix(limit))
    }
}

/// Follow Up Today section content.
nonisolated enum FollowUpTodayState: Equatable {
    /// Rows to show plus how many more are due today than fit.
    case due(count: Int, overflow: Int)
    /// "Nothing due today. {N} coming up."
    case nothingDue(upcoming: Int)
    /// "No follow-ups yet. …"
    case noFollowUps

    static func make(dueCount: Int, upcoming: Int, limit: Int = HomeSelection.followUpLimit) -> FollowUpTodayState {
        if dueCount > 0 { return .due(count: min(dueCount, limit), overflow: max(dueCount - limit, 0)) }
        return upcoming > 0 ? .nothingDue(upcoming: upcoming) : .noFollowUps
    }
}

/// Compact relative time for Recent rows: "now", "5m", "3h", "2d", "1mo", "1y".
nonisolated enum CompactRelativeTime {
    static func string(from date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        let minutes = Int(seconds / 60)
        let hours = minutes / 60
        let days = hours / 24
        switch seconds {
        case ..<60: return String(localized: "now", bundle: .appStrings)
        case ..<3_600: return String(localized: "\(minutes)m", bundle: .appStrings)
        case ..<86_400: return String(localized: "\(hours)h", bundle: .appStrings)
        default:
            if days < 30 { return String(localized: "\(days)d", bundle: .appStrings) }
            if days < 365 { return String(localized: "\(days / 30)mo", bundle: .appStrings) }
            return String(localized: "\(days / 365)y", bundle: .appStrings)
        }
    }
}
