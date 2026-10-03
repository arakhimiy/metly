import Foundation

/// One FOLLOWUPS section.
nonisolated struct FollowUpGroup<Item>: Identifiable {
    let bucket: FollowUpBucket
    var items: [Item]

    var id: FollowUpBucket { bucket }
}

nonisolated enum FollowUpGrouping {
    /// Groups reminders into non-empty buckets in display order. Open buckets are sorted by due date
    /// (earliest first); Done is sorted by completion (most recent first).
    static func groups<Item: FollowUpItem>(_ items: [Item], now: Date, calendar: Calendar) -> [FollowUpGroup<Item>] {
        let byBucket = Dictionary(grouping: items) {
            FollowUpBucket.bucket(dueAt: $0.dueAt, isDone: $0.isDone, now: now, calendar: calendar)
        }
        return FollowUpBucket.allCases.compactMap { bucket in
            guard let members = byBucket[bucket], !members.isEmpty else { return nil }
            let sorted = bucket == .done
                ? members.sorted { ($0.completedAt ?? $0.dueAt) > ($1.completedAt ?? $1.dueAt) }
                : members.sorted { $0.dueAt < $1.dueAt }
            return FollowUpGroup(bucket: bucket, items: sorted)
        }
    }
}
