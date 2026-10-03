import Foundation

/// Pure rules turning verified subscription records into the app's plan.
nonisolated enum EntitlementMapper {
    /// Whether a single record grants Pro right now.
    static func grantsPro(_ record: SubscriptionRecord, now: Date) -> Bool {
        guard ProProduct(productID: record.productID) != nil,
              record.revocationDate == nil,
              !record.isUpgraded else { return false }

        switch record.state {
        case .subscribed:
            return true
        case .inGracePeriod:
            // Apple keeps access during the billing grace period.
            return (record.gracePeriodExpirationDate ?? .distantFuture) > now
        case .inBillingRetryPeriod, .expired, .revoked:
            return false
        case nil:
            // Status unavailable (e.g. offline): fall back to the transaction's own expiry.
            return (record.expirationDate ?? .distantFuture) > now
        }
    }

    /// Picks the active record that lasts longest and maps it to an `EntitlementSnapshot`.
    static func snapshot(from records: [SubscriptionRecord], now: Date) -> EntitlementSnapshot {
        let active = records.filter { grantsPro($0, now: now) }
        guard let best = active.max(by: { endDate(of: $0) < endDate(of: $1) }) else { return .free }

        let willRenew = best.willAutoRenew ?? false
        let renewsAt: Date? = if best.state == .inGracePeriod {
            best.gracePeriodExpirationDate ?? best.expirationDate
        } else {
            best.renewalDate ?? best.expirationDate
        }
        return EntitlementSnapshot(isPro: true, productID: best.productID, renewsAt: renewsAt, willRenew: willRenew)
    }

    private static func endDate(of record: SubscriptionRecord) -> Date {
        record.renewalDate ?? record.expirationDate ?? .distantFuture
    }
}
