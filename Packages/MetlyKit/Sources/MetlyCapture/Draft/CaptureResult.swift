import Foundation

/// What `CaptureDraft.apply(to:in:limits:)` did.
public struct CaptureResult: Equatable, Sendable {
    public enum FollowUpOutcome: Equatable, Sendable {
        /// No follow-up was picked.
        case none
        /// A new reminder was created.
        case scheduled(id: UUID)
        /// The person's open reminder was moved (one open reminder per person).
        case rescheduled(id: UUID)
        /// Free plan limit: nothing was created. Show `.followUpLimitAlert`.
        case limitReached(openCount: Int)
    }

    public var followUp: FollowUpOutcome

    public init(followUp: FollowUpOutcome) {
        self.followUp = followUp
    }

    public var reminderSet: Bool {
        switch followUp {
        case .scheduled, .rescheduled: true
        case .none, .limitReached: false
        }
    }

    public var hitFollowUpLimit: Bool {
        if case .limitReached = followUp { return true }
        return false
    }

    /// The id of the scheduled / rescheduled reminder.
    public var followUpID: UUID? {
        switch followUp {
        case .scheduled(let id), .rescheduled(let id): id
        case .none, .limitReached: nil
        }
    }

    /// "Saved · Reminder Set" when a reminder was scheduled, otherwise `fallback`
    /// (e.g. "Connection Saved", "Context Saved", "Contact Saved").
    public func toastMessage(otherwise fallback: String) -> String {
        reminderSet ? String(localized: "Saved · Reminder Set", bundle: .appStrings) : fallback
    }
}
