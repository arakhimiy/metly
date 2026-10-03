import Foundation

/// Metly Pro auto-renewable subscriptions (subscription group "Metly Pro", see `Metly/Metly.storekit`).
nonisolated public enum ProProduct: String, CaseIterable, Sendable {
    case yearly = "com.metly.app.pro.yearly"
    case monthly = "com.metly.app.pro.monthly"

    /// Every Pro product ID, yearly first (the recommended plan).
    public static let allIDs: [String] = allCases.map(\.rawValue)

    public var id: String { rawValue }

    /// "Yearly" / "Monthly" — used in "Pro · Yearly".
    public var periodTitle: String {
        switch self {
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        }
    }

    public init?(productID: String?) {
        guard let productID, let product = ProProduct(rawValue: productID) else { return nil }
        self = product
    }
}
