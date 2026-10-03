import Foundation

/// Decides when two UWB iPhones are "tapped" from NearbyInteraction distance samples.
///
/// Fires once when the distance drops to `threshold` (10 cm, PLAN Q7) or below; re-arms only after
/// the phones move apart beyond `rearmDistance`, so holding them together doesn't fire repeatedly
/// and sensor jitter around the threshold doesn't either.
nonisolated struct TapProximity: Equatable, Sendable {
    /// Distance that counts as a tap (meters).
    static let threshold: Float = 0.10
    /// Distance the phones must exceed before another tap can fire (meters).
    static let rearmDistance: Float = 0.30

    private(set) var isArmed = true
    private(set) var lastDistance: Float?

    init() {}

    /// Feeds a distance sample (nil = not available in this update). Returns true when a tap fires.
    mutating func update(distance: Float?) -> Bool {
        guard let distance, distance.isFinite, distance >= 0 else { return false }
        lastDistance = distance
        if isArmed, distance <= Self.threshold {
            isArmed = false
            return true
        }
        if !isArmed, distance > Self.rearmDistance {
            isArmed = true
        }
        return false
    }

    /// Whether a sample is inside the tap distance (no state change).
    static func isTap(_ distance: Float?) -> Bool {
        guard let distance, distance.isFinite, distance >= 0 else { return false }
        return distance <= threshold
    }
}
