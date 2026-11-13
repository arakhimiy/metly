import Foundation

/// CONNECT's two modes (segmented control).
nonisolated enum ConnectMode: String, CaseIterable, Identifiable, Sendable {
    case nearby, tapPhones

    var id: String { rawValue }

    /// Modes shown in CONNECT. Tap Phones is off: it needs Nameshake open on both phones and adds little
    /// over Nearby (AirDrop / NameDrop cover the system side). Its code stays for a later return.
    static let offered: [ConnectMode] = [.nearby]

    var title: String {
        switch self {
        case .nearby: String(localized: "Nearby")
        case .tapPhones: String(localized: "Tap Phones")
        }
    }
}
