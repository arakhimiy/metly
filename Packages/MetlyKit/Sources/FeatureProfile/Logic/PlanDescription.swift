import Foundation
import MetlyCore

/// Copy for the plan rows in PROFILE and SETTINGS_SUBSCRIPTION.
nonisolated enum PlanDescription {
    /// "Free", "Pro · Yearly", "Pro · Monthly" or "Pro".
    static func title(isPro: Bool, productID: String?) -> String {
        guard isPro else { return String(localized: "Free") }
        guard let product = ProProduct(productID: productID) else { return String(localized: "Pro") }
        return String(localized: "Pro · \(product.periodTitle)")
    }

    /// "1 of 2" on a limited plan, "3 · Unlimited" otherwise.
    static func usage(_ count: Int, limit: Int?) -> String {
        guard let limit else { return String(localized: "\(count) · Unlimited") }
        return String(localized: "\(count) of \(limit)")
    }
}
