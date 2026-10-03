import Foundation
import Testing
@testable import FeatureScan

@Suite("Duplicate-detection debounce")
struct ScanDebouncerTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let kamila = "https://metly.link/c/kamila-x1y2"
    private let sardor = "https://metly.link/c/sardor-r4t5"
    private let web = "https://example.com"

    /// A camera sighting: payload, seconds after `start`, whether the screen is blocked.
    private struct Sighting {
        var payload: String
        var time: TimeInterval
        var blocked = false
    }

    /// Feeds sightings in order and returns which ones were handled.
    private func run(_ debouncer: inout ScanDebouncer, _ sightings: [Sighting]) -> [Bool] {
        sightings.map { sighting in
            debouncer.shouldHandle(sighting.payload, at: start.addingTimeInterval(sighting.time), isBlocked: sighting.blocked)
        }
    }

    @Test("The first sighting is handled")
    func firstSighting() {
        var debouncer = ScanDebouncer()
        #expect(run(&debouncer, [Sighting(payload: kamila, time: 0)]) == [true])
    }

    @Test("A code that stays in view is handled once")
    func staysInView() {
        var debouncer = ScanDebouncer()
        // AVFoundation reports the code on every frame.
        let frames = stride(from: 0.0, through: 10, by: 0.1).map { Sighting(payload: kamila, time: $0) }
        let handled = run(&debouncer, frames)
        #expect(handled.first == true)
        #expect(handled.dropFirst().allSatisfy { !$0 })
    }

    @Test("The same code is handled again after it left the frame")
    func leavesAndReturns() {
        var debouncer = ScanDebouncer(interval: 2)
        let handled = run(&debouncer, [
            Sighting(payload: kamila, time: 0),
            Sighting(payload: kamila, time: 1),
            Sighting(payload: kamila, time: 3.5),
        ])
        #expect(handled == [true, false, true])
    }

    @Test("Different codes are at least the minimum gap apart")
    func minimumGap() {
        var debouncer = ScanDebouncer(interval: 2, minimumGap: 1)
        let handled = run(&debouncer, [
            Sighting(payload: kamila, time: 0),
            Sighting(payload: sardor, time: 0.5),    // too soon after Kamila
            Sighting(payload: sardor, time: 1.5),    // still in view → waits until it leaves
            Sighting(payload: sardor, time: 4),
            Sighting(payload: web, time: 5.5),
        ])
        #expect(handled == [true, false, false, true, true])
    }

    @Test("Sightings while blocked (alert up) keep the code suppressed")
    func blockedSightingsCount() {
        var debouncer = ScanDebouncer(interval: 2)
        let handled = run(&debouncer, [
            Sighting(payload: web, time: 0),
            Sighting(payload: web, time: 1, blocked: true),
            Sighting(payload: web, time: 2, blocked: true),
            Sighting(payload: web, time: 3, blocked: true),
            Sighting(payload: web, time: 3.5),       // alert dismissed, code still in view: no second alert
            Sighting(payload: web, time: 6),
        ])
        #expect(handled == [true, false, false, false, false, true])
    }

    @Test("Pause ignores everything; the code seen during the pause stays suppressed while in view")
    func pause() {
        var debouncer = ScanDebouncer(interval: 2, minimumGap: 1)
        debouncer.pause(for: 1.5, from: start)
        let handled = run(&debouncer, [
            Sighting(payload: kamila, time: 0.2),
            Sighting(payload: kamila, time: 1.4),
            Sighting(payload: kamila, time: 2.0),    // seen 0.6 s ago
            Sighting(payload: sardor, time: 2.0),    // a new code after the pause
        ])
        #expect(handled == [false, false, false, true])
    }
}
