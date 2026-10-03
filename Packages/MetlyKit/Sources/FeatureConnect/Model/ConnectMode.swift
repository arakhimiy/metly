import Foundation

/// CONNECT's two modes (segmented control).
nonisolated enum ConnectMode: String, CaseIterable, Identifiable, Sendable {
    case nearby, tapPhones

    var id: String { rawValue }

    var title: String {
        switch self {
        case .nearby: "Nearby"
        case .tapPhones: "Tap Phones"
        }
    }
}
