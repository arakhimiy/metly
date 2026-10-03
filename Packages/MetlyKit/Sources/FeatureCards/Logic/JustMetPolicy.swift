import Foundation
import MetlyCore

/// "Who did you just meet?" heuristic (SPEC §3.8, §9 Q43):
/// - after QR_FULLSCREEN was visible for more than 2 s, or
/// - after SHARE_SHEET closes once the user performed a share action,
/// but never more than once every 10 minutes so it doesn't nag at a busy event.
nonisolated enum JustMetPolicy {
    static let minimumQRVisibleDuration: TimeInterval = 2
    static let cooldown: TimeInterval = 10 * 60

    static func isCoolingDown(lastPromptAt: Date?, now: Date) -> Bool {
        guard let lastPromptAt else { return false }
        let elapsed = now.timeIntervalSince(lastPromptAt)
        // A negative interval means the clock moved back — don't block forever.
        return elapsed >= 0 && elapsed < cooldown
    }

    static func shouldPromptAfterQR(shownAt: Date, now: Date, lastPromptAt: Date?) -> Bool {
        now.timeIntervalSince(shownAt) > minimumQRVisibleDuration && !isCoolingDown(lastPromptAt: lastPromptAt, now: now)
    }

    static func shouldPromptAfterShare(didShare: Bool, now: Date, lastPromptAt: Date?) -> Bool {
        didShare && !isCoolingDown(lastPromptAt: lastPromptAt, now: now)
    }
}

/// Applies `JustMetPolicy` against the persisted timestamp. `AppPreferences.lastQRShownAt` is the
/// anchor of the rate limit: it is recorded only when the sheet is actually offered.
@MainActor
enum JustMetPrompter {
    static func claimAfterQR(shownAt: Date, preferences: AppPreferences, now: Date = .now) -> Bool {
        guard JustMetPolicy.shouldPromptAfterQR(shownAt: shownAt, now: now, lastPromptAt: preferences.lastQRShownAt)
        else { return false }
        preferences.lastQRShownAt = now
        return true
    }

    static func claimAfterShare(didShare: Bool, preferences: AppPreferences, now: Date = .now) -> Bool {
        guard JustMetPolicy.shouldPromptAfterShare(didShare: didShare, now: now, lastPromptAt: preferences.lastQRShownAt)
        else { return false }
        preferences.lastQRShownAt = now
        return true
    }
}
