import Foundation

/// Tanishly Pro auto-renewable subscriptions (subscription group "Tanishly Pro", see `Metly/Metly.storekit`).
nonisolated public enum ProProduct: String, CaseIterable, Sendable {
    case yearly = "app.tanishly.ios.pro.yearly"
    case monthly = "app.tanishly.ios.pro.monthly"

    /// Every Pro product ID, yearly first (the recommended plan).
    public static let allIDs: [String] = allCases.map(\.rawValue)

    public var id: String { rawValue }

    /// "Yearly" / "Monthly" — used in "Pro · Yearly".
    public var periodTitle: String {
        switch self {
        case .yearly: String(localized: "Yearly")
        case .monthly: String(localized: "Monthly")
        }
    }

    public init?(productID: String?) {
        guard let productID, let product = ProProduct(rawValue: productID) else { return nil }
        self = product
    }
}
