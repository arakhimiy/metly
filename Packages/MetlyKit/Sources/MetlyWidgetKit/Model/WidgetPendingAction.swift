import Foundation

/// Something a widget did that the app must apply to its store (the extension never writes SwiftData).
///
/// Interactive widget buttons append actions to a queue file in the App Group; the app's
/// `WidgetSnapshotPublisher` applies them on launch / activation and removes them, while the widget
/// overlays pending actions on the last snapshot so the tap shows immediately.
nonisolated public struct WidgetPendingAction: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// Mark a follow-up done (`targetID` = FollowUp id).
        case completeFollowUp
    }

    public var id: UUID
    public var kind: Kind
    public var targetID: UUID
    /// When the user tapped — becomes the follow-up's `completedAt`.
    public var createdAt: Date

    public init(id: UUID = UUID(), kind: Kind, targetID: UUID, createdAt: Date = .now) {
        self.id = id
        self.kind = kind
        self.targetID = targetID
        self.createdAt = createdAt
    }

    public static func completeFollowUp(_ followUpID: UUID, at date: Date = .now) -> WidgetPendingAction {
        WidgetPendingAction(kind: .completeFollowUp, targetID: followUpID, createdAt: date)
    }
}

/// A follow-up the app should mark done.
nonisolated public struct WidgetFollowUpCompletion: Hashable, Sendable {
    public var followUpID: UUID
    public var completedAt: Date

    public init(followUpID: UUID, completedAt: Date) {
        self.followUpID = followUpID
        self.completedAt = completedAt
    }
}

/// The queue reduced to the work the app has to do: one completion per follow-up (the first tap
/// wins), plus which queued actions each completion settles.
nonisolated public struct WidgetPendingActionPlan: Sendable {
    public let completions: [WidgetFollowUpCompletion]
    private let actionIDsByFollowUp: [UUID: [UUID]]

    public init(_ actions: [WidgetPendingAction]) {
        var completions: [WidgetFollowUpCompletion] = []
        var actionIDs: [UUID: [UUID]] = [:]
        for action in actions.sorted(by: { $0.createdAt < $1.createdAt }) {
            switch action.kind {
            case .completeFollowUp:
                if actionIDs[action.targetID] == nil {
                    completions.append(WidgetFollowUpCompletion(followUpID: action.targetID, completedAt: action.createdAt))
                }
                actionIDs[action.targetID, default: []].append(action.id)
            }
        }
        self.completions = completions
        self.actionIDsByFollowUp = actionIDs
    }

    public var isEmpty: Bool { completions.isEmpty }

    /// Queue entries to delete once these follow-ups were handled (applied, or no longer applicable).
    public func actionIDs(settledBy followUpIDs: Set<UUID>) -> Set<UUID> {
        Set(followUpIDs.flatMap { actionIDsByFollowUp[$0] ?? [] })
    }
}

nonisolated extension WidgetSnapshot {
    /// The snapshot as it will look once the app applied `actions` (optimistic widget state).
    public func applying(_ actions: [WidgetPendingAction]) -> WidgetSnapshot {
        let completed = Set(actions.filter { $0.kind == .completeFollowUp }.map(\.targetID))
        guard !completed.isEmpty else { return self }
        var copy = self
        for followUp in followUps where completed.contains(followUp.id) {
            if let index = copy.openFollowUpDueDates.firstIndex(of: followUp.dueAt) {
                copy.openFollowUpDueDates.remove(at: index)
            }
        }
        copy.followUps.removeAll { completed.contains($0.id) }
        return copy
    }
}
