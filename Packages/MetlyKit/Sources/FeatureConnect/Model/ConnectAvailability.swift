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

/// Whether discovery can run, and why not.
nonisolated enum ConnectAvailability: Equatable, Sendable {
    case starting
    case active
    /// Privacy › "Show in Nearby" is off: explain and offer to turn it on.
    case hiddenFromNearby
    case localNetworkDenied
    case offline
    case failed(String)

    var isBlocking: Bool {
        switch self {
        case .starting, .active: false
        case .hiddenFromNearby, .localNetworkDenied, .offline, .failed: true
        }
    }
}

/// Tap Phones progress shown on the Tap Phones page.
nonisolated enum TapStatus: Equatable, Sendable {
    /// Waiting for phones to touch.
    case ready
    /// Phones touched; this phone sends the request (the machine is `.waiting`).
    case detected(NearbyPerson)
    /// Phones touched; the other phone sends the request — INCOMING_REQUEST follows.
    case receiving(NearbyPerson)
}
