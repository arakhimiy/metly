import Foundation
import Testing
@testable import FeatureConnect

/// Feeds samples in order and returns which ones fired a tap.
private func taps(_ samples: [Float?], _ proximity: inout TapProximity) -> [Bool] {
    samples.map { proximity.update(distance: $0) }
}

struct TapProximityTests {
    @Test func firesAtTenCentimetresOrCloser() {
        var proximity = TapProximity()
        let fired = taps([0.5, 0.12, 0.10], &proximity)
        #expect(fired == [false, false, true])   // threshold is inclusive
        #expect(TapProximity.threshold == 0.10)
    }

    @Test func ignoresMissingAndInvalidSamples() {
        var proximity = TapProximity()
        let fired = taps([nil, .nan, -0.01, .infinity], &proximity)
        #expect(fired == [false, false, false, false])
        #expect(proximity.lastDistance == nil)
        #expect(proximity.isArmed)
    }

    @Test func holdingPhonesTogetherFiresOnce() {
        var proximity = TapProximity()
        // Jitter around the threshold (0.15 → 0.09) doesn't re-arm either.
        let fired = taps([0.08, 0.05, 0.02, 0.15, 0.09], &proximity)
        #expect(fired == [true, false, false, false, false])
        #expect(!proximity.isArmed)
    }

    @Test func rearmsAfterMovingApart() {
        var proximity = TapProximity()
        let close = taps([0.06, 0.30], &proximity)   // 0.30 isn't beyond the re-arm distance
        #expect(close == [true, false])
        #expect(!proximity.isArmed)
        let apart = taps([0.31], &proximity)
        #expect(apart == [false])
        #expect(proximity.isArmed)
        let again = taps([0.07], &proximity)
        #expect(again == [true])
    }

    @Test func staticCheck() {
        #expect(TapProximity.isTap(0.1))
        #expect(TapProximity.isTap(0))
        #expect(!TapProximity.isTap(0.1001))
        #expect(!TapProximity.isTap(nil))
    }
}

struct BumpTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func detectsSpikesWithRefractoryPeriod() {
        var detector = BumpDetector()
        let samples: [(magnitude: Double, offset: TimeInterval)] = [
            (0.4, 0),      // walking
            (2.1, 0),
            (2.4, 0.3),    // the same bump ringing
            (1.7, 0.9),
            (.nan, 5),
        ]
        let bumps = samples.map { detector.process(magnitude: $0.magnitude, at: start.addingTimeInterval($0.offset)) }
        #expect(bumps == [false, true, false, true, false])
    }

    @Test func magnitudeIsEuclidean() {
        #expect(BumpDetector.magnitude(x: 3, y: 4, z: 0) == 5)
    }

    @Test func ownBumpThenPeerBumpMatches() {
        var matcher = BumpMatcher<String>()
        let own = matcher.recordOwnBump(at: start)
        let peer = matcher.recordPeerBump(from: "kamila", at: start.addingTimeInterval(0.4))
        #expect(own.isEmpty)
        #expect(peer)
    }

    @Test func peerBumpThenOwnBumpMatches() {
        var matcher = BumpMatcher<String>()
        let kamila = matcher.recordPeerBump(from: "kamila", at: start)
        let sardor = matcher.recordPeerBump(from: "sardor", at: start.addingTimeInterval(-2))
        let matches = matcher.recordOwnBump(at: start.addingTimeInterval(0.3))
        #expect(!kamila)
        #expect(!sardor)
        #expect(matches == ["kamila"])
    }

    @Test func bumpsTooFarApartDontMatch() {
        var matcher = BumpMatcher<String>()
        _ = matcher.recordOwnBump(at: start)
        let late = matcher.recordPeerBump(from: "kamila", at: start.addingTimeInterval(1.5))
        let muchLater = matcher.recordOwnBump(at: start.addingTimeInterval(3))
        #expect(!late)
        #expect(muchLater.isEmpty)
    }

    @Test func aBumpMatchesOnlyOnce() {
        var matcher = BumpMatcher<String>()
        _ = matcher.recordOwnBump(at: start)
        let first = matcher.recordPeerBump(from: "kamila", at: start.addingTimeInterval(0.1))
        let second = matcher.recordPeerBump(from: "kamila", at: start.addingTimeInterval(0.2))
        #expect(first)
        #expect(!second)
    }
}

struct TapHandshakeTests {
    @Test func exactlyOnePhoneSendsTheRequest() {
        let a = "mock-self-1a2b"
        let b = "mock-self-9z8y"
        #expect(TapHandshake.initiatesRequest(ownToken: a, peerToken: b))
        #expect(!TapHandshake.initiatesRequest(ownToken: b, peerToken: a))
    }

    @Test func unknownOwnTokenInitiates() {
        #expect(TapHandshake.initiatesRequest(ownToken: nil, peerToken: "x"))
        #expect(TapHandshake.initiatesRequest(ownToken: "", peerToken: "x"))
    }

    @Test func messagesRoundTrip() throws {
        let token = TapMessage.rangingToken(Data([1, 2, 3]))
        #expect(TapMessage(data: try #require(token.encoded)) == token)
        #expect(TapMessage(data: try #require(TapMessage.bump.encoded)) == .bump)
        #expect(TapMessage(data: Data("nonsense".utf8)) == nil)
    }
}
