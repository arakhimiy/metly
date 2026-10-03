import Foundation

/// What a Tap Phones gesture can be detected with on this iPhone.
nonisolated enum TapCapability: Equatable, Sendable {
    /// Ultra Wideband: NearbyInteraction measures the distance (≤ 10 cm counts as a tap).
    case preciseDistance
    /// No UWB: both phones feel the bump (accelerometer) and match it over the local link.
    case bump
    /// Neither is available (e.g. the simulator without the demo world).
    case unsupported
}

/// Another phone was tapped against this one.
nonisolated struct TapDetection: Equatable, Sendable {
    enum Signal: Equatable, Sendable { case distance, bump, simulated }

    /// The other phone's server discovery token.
    var token: String
    var signal: Signal
    /// Whether this phone sends the connect request (the other one receives it as INCOMING_REQUEST).
    var initiatesRequest: Bool
}

/// Both tapped phones detect the gesture at the same moment; only one may send the request or
/// each would get the other's request on top of its own. The phone with the smaller discovery
/// token sends it — both sides compute the same answer without talking to each other.
nonisolated enum TapHandshake {
    static func initiatesRequest(ownToken: String?, peerToken: String) -> Bool {
        guard let ownToken, !ownToken.isEmpty else { return true }
        return ownToken < peerToken
    }

    /// How long the receiving phone waits for the initiator's request before giving up.
    static let receiveTimeout: Duration = .seconds(15)
    /// The same phone isn't detected twice within this interval.
    static let repeatInterval: TimeInterval = 5
}
