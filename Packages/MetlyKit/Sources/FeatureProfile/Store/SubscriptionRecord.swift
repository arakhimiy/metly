import Foundation

/// StoreKit-free snapshot of one verified subscription transaction plus its renewal status.
/// `SubscriptionManager` builds these from `Transaction` / `Product.SubscriptionInfo.Status`
/// so the entitlement rules in `EntitlementMapper` stay unit-testable.
nonisolated struct SubscriptionRecord: Equatable, Sendable {
    enum RenewalState: Equatable, Sendable {
        case subscribed
        case inGracePeriod
        case inBillingRetryPeriod
        case expired
        case revoked
    }

    var productID: String
    var purchaseDate: Date
    var expirationDate: Date?
    var revocationDate: Date?
    /// A newer transaction superseded this one (upgrade inside the group).
    var isUpgraded: Bool = false
    /// nil when the renewal status couldn't be loaded.
    var state: RenewalState?
    var willAutoRenew: Bool?
    var renewalDate: Date?
    var gracePeriodExpirationDate: Date?
}

/// What the app shows / gates on. Applied to `Entitlements` in MetlyCore.
nonisolated struct EntitlementSnapshot: Equatable, Sendable {
    var isPro: Bool
    var productID: String?
    var renewsAt: Date?
    var willRenew: Bool

    static let free = EntitlementSnapshot(isPro: false, productID: nil, renewsAt: nil, willRenew: false)
}
