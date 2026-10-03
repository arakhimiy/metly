import Foundation

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
