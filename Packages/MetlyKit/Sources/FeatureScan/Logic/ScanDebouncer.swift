import Foundation

/// Filters repeated QR detections. Cameras report the same code many times per second
/// (AVFoundation every frame, VisionKit whenever it re-acquires the code), so:
/// • a code is handled again only after it has been **out of view** for `interval`
///   (every sighting extends the window, even while handling is blocked by an alert or push);
/// • two different codes are never handled less than `minimumGap` apart;
/// • `pause(for:)` ignores everything for a moment (e.g. right after coming back to SCAN,
///   so the code that was just handled doesn't immediately re-open its card).
nonisolated struct ScanDebouncer: Sendable {
    var interval: TimeInterval = 2
    var minimumGap: TimeInterval = 1

    private var lastSeen: [String: Date] = [:]
    private var lastHandledAt: Date?
    private var quietUntil: Date?

    init(interval: TimeInterval = 2, minimumGap: TimeInterval = 1) {
        self.interval = interval
        self.minimumGap = minimumGap
    }

    /// Records a sighting and returns whether it should be acted on.
    /// - Parameter isBlocked: the screen can't react right now (alert up, not visible); the sighting still counts.
    mutating func shouldHandle(_ payload: String, at now: Date = .now, isBlocked: Bool = false) -> Bool {
        let previous = lastSeen[payload]
        lastSeen[payload] = now
        if lastSeen.count > 16 { prune(now: now) }

        if isBlocked { return false }
        if let quietUntil, now < quietUntil { return false }
        if let previous, now.timeIntervalSince(previous) < interval { return false }
        if let lastHandledAt, now.timeIntervalSince(lastHandledAt) < minimumGap { return false }
        lastHandledAt = now
        return true
    }

    /// Ignores every detection for `duration` (sightings are still recorded).
    mutating func pause(for duration: TimeInterval, from now: Date = .now) {
        quietUntil = now.addingTimeInterval(duration)
    }

    private mutating func prune(now: Date) {
        lastSeen = lastSeen.filter { now.timeIntervalSince($0.value) < interval * 4 }
    }
}
