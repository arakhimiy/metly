import Foundation

/// Nameshake Pro auto-renewable subscriptions (subscription group "Nameshake Pro", see `Metly/Metly.storekit`).
nonisolated public enum ProProduct: String, CaseIterable, Sendable {
    case yearly = "app.nameshake.ios.pro.yearly"
    case monthly = "app.nameshake.ios.pro.monthly"

    /// Every Pro product ID, yearly first (the recommended plan).
    public static let allIDs: [String] = allCases.map(\.rawValue)

    public var id: String { rawValue }

    /// "Yearly" / "Monthly" — used in "Pro · Yearly".
    public var periodTitle: String {
        switch self {
        case .yearly: String(localized: "Yearly", bundle: .appStrings)
        case .monthly: String(localized: "Monthly", bundle: .appStrings)
        }
    }

    public init?(productID: String?) {
        guard let productID, let product = ProProduct(rawValue: productID) else { return nil }
        self = product
    }
}
