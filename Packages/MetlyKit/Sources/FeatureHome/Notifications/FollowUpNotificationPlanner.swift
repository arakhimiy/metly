import Foundation
import MetlyCore

/// Decides which follow-ups get a pending local notification.
nonisolated enum FollowUpNotificationPlanner {
    /// iOS keeps at most 64 pending local notifications per app; leave headroom for other features.
    static let maxPending = 60

    /// A reminder as the planner sees it (built from `FollowUp` + its person on the main actor).
    struct Candidate: Equatable, Sendable {
        var id: UUID
        var personName: String
        var what: String
        var channel: FollowUpChannel
        var hasChannelValue: Bool
        var dueAt: Date
        var isOpen: Bool
    }

    /// Payloads for every open reminder due in the future, earliest first, capped at `maxPending`.
    /// Nothing when follow-up reminders are turned off (or delivered by the Telegram bot instead).
    /// - Parameter timeZone: the zone the triggers' wall-clock components are computed in.
    static func payloads(for candidates: [Candidate], now: Date, enabled: Bool,
                         timeZone: TimeZone = .current,
                         limit: Int = maxPending) -> [FollowUpNotificationPayload] {
        guard enabled else { return [] }
        return candidates
            .filter { $0.isOpen && $0.dueAt > now }
            .sorted { $0.dueAt < $1.dueAt }
            .prefix(limit)
            .map {
                FollowUpNotificationPayload(followUpID: $0.id, personName: $0.personName, what: $0.what,
                                            channel: $0.channel, hasChannelValue: $0.hasChannelValue, dueAt: $0.dueAt,
                                            timeZone: timeZone)
            }
    }

    /// Local pushes are on when the profile allows follow-up reminders.
    static func isEnabled(prefs: NotificationPrefs?) -> Bool {
        guard let prefs else { return false }
        return prefs.followUpReminders
    }

    /// Pending identifiers that no longer match a desired payload (done, deleted, moved past, turned off).
    static func staleIdentifiers(pending: [String], desired: [FollowUpNotificationPayload]) -> [String] {
        let wanted = Set(desired.map(\.identifier))
        return pending.filter { $0.hasPrefix(FollowUpNotificationPayload.identifierPrefix) && !wanted.contains($0) }
    }

    /// Desired payloads that are missing or changed compared with what's pending (identifier → fingerprint).
    static func payloadsToAdd(desired: [FollowUpNotificationPayload],
                              pendingFingerprints: [String: String]) -> [FollowUpNotificationPayload] {
        desired.filter { pendingFingerprints[$0.identifier] != $0.fingerprint }
    }
}
