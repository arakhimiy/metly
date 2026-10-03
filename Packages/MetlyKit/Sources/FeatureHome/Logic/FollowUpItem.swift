import Foundation
import MetlyData

/// The scheduling facts the grouping / Home rules need — lets tests use plain values instead of models.
nonisolated protocol FollowUpItem {
    var dueAt: Date { get }
    var isDone: Bool { get }
    var completedAt: Date? { get }
}

extension FollowUp: FollowUpItem {}

/// The facts the Recent ordering needs.
nonisolated protocol RecentPersonItem {
    /// When the owner last met them (latest meeting context).
    var metAt: Date { get }
    var createdAt: Date { get }
}

extension Connection: RecentPersonItem {
    nonisolated var metAt: Date { context.metAt }
}
