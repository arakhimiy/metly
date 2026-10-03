import Foundation

/// Tap Phones progress shown on the Tap Phones page.
nonisolated enum TapStatus: Equatable, Sendable {
    /// Waiting for phones to touch.
    case ready
    /// Phones touched; this phone sends the request (the machine is `.waiting`).
    case detected(NearbyPerson)
    /// Phones touched; the other phone sends the request — INCOMING_REQUEST follows.
    case receiving(NearbyPerson)
}
