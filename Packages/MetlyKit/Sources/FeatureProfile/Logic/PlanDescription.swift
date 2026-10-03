import Foundation
import MetlyCore

/// Copy for the plan rows in PROFILE and SETTINGS_SUBSCRIPTION.
nonisolated enum PlanDescription {
    /// "Free", "Pro · Yearly", "Pro · Monthly" or "Pro".
    static func title(isPro: Bool, productID: String?) -> String {
        guard isPro else { return "Free" }
        guard let product = ProProduct(productID: productID) else { return "Pro" }
        return "Pro · \(product.periodTitle)"
    }

    /// "1 of 2" on a limited plan, "3 · Unlimited" otherwise.
    static func usage(_ count: Int, limit: Int?) -> String {
        guard let limit else { return "\(count) · Unlimited" }
        return "\(count) of \(limit)"
    }
}
