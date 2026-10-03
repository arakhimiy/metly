import Foundation

/// FOLLOWUPS groups (SPEC §2.5.14): Overdue · Today · This Week (1–6 days) · Later (≥ 7 days) · Done.
nonisolated enum FollowUpBucket: String, CaseIterable, Identifiable, Sendable {
    case overdue, today, thisWeek, later, done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overdue: String(localized: "Overdue")
        case .today: String(localized: "Today")
        case .thisWeek: String(localized: "This Week")
        case .later: String(localized: "Later")
        case .done: String(localized: "Done")
        }
    }

    /// Calendar-day bucket: a reminder due earlier today is still "Today", not "Overdue".
    static func bucket(dueAt: Date, isDone: Bool, now: Date, calendar: Calendar) -> FollowUpBucket {
        if isDone { return .done }
        switch FollowUpDates.dayOffset(from: now, to: dueAt, calendar: calendar) {
        case ..<0: return .overdue
        case 0: return .today
        case 1...6: return .thisWeek
        default: return .later
        }
    }
}

/// How the due label is tinted (red overdue, tint today, secondary otherwise).
nonisolated enum DueEmphasis: Sendable {
    case overdue, today, upcoming, done

    static func of(dueAt: Date, isDone: Bool, now: Date, calendar: Calendar) -> DueEmphasis {
        switch FollowUpBucket.bucket(dueAt: dueAt, isDone: isDone, now: now, calendar: calendar) {
        case .overdue: .overdue
        case .today: .today
        case .thisWeek, .later: .upcoming
        case .done: .done
        }
    }
}
