import Foundation

/// Spots a deliberate "bump" (two phones tapped together) in user-acceleration samples, for
/// iPhones without Ultra Wideband. A short spike above `threshold`, at most once per `refractory`.
nonisolated struct BumpDetector: Equatable, Sendable {
    /// User-acceleration magnitude (g) that counts as a bump. Walking stays well below ~0.6 g.
    static let threshold = 1.6
    /// Minimum time between two bumps.
    static let refractory: TimeInterval = 0.8

    private(set) var lastBump: Date?

    init() {}

    /// Feeds one sample; returns true when it's a new bump.
    mutating func process(magnitude: Double, at date: Date) -> Bool {
        guard magnitude.isFinite, magnitude >= Self.threshold else { return false }
        if let lastBump, date.timeIntervalSince(lastBump) < Self.refractory { return false }
        lastBump = date
        return true
    }

    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }
}

/// Pairs this phone's bump with a peer's: both phones report a bump to each other over the local
/// link, and a tap is when both happened within `window` (measured on this phone's clock, so device
/// clock skew doesn't matter).
nonisolated struct BumpMatcher<Peer: Hashable & Sendable>: Sendable {
    static var window: TimeInterval { 0.7 }

    private var ownBump: Date?
    private var peerBumps: [Peer: Date] = [:]

    init() {}

    /// This phone bumped: returns the peers whose bump arrived within the window.
    mutating func recordOwnBump(at date: Date) -> [Peer] {
        ownBump = date
        prune(now: date)
        let matches = peerBumps.filter { abs($0.value.timeIntervalSince(date)) <= Self.window }.map(\.key)
        for peer in matches { peerBumps[peer] = nil }
        return matches
    }

    /// A peer told us it bumped: true when it matches this phone's recent bump.
    mutating func recordPeerBump(from peer: Peer, at date: Date) -> Bool {
        prune(now: date)
        if let ownBump, abs(date.timeIntervalSince(ownBump)) <= Self.window {
            self.ownBump = nil
            return true
        }
        peerBumps[peer] = date
        return false
    }

    private mutating func prune(now: Date) {
        peerBumps = peerBumps.filter { now.timeIntervalSince($0.value) <= Self.window }
        if let ownBump, now.timeIntervalSince(ownBump) > Self.window { self.ownBump = nil }
    }
}
