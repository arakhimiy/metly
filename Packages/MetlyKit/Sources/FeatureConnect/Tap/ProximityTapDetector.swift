import CoreMotion
import Foundation
@preconcurrency import NearbyInteraction
import Observation

/// Real-device Tap Phones detection (PLAN Q7):
/// - **UWB iPhones**: swap `NIDiscoveryToken`s over the transport link and range with
///   NearbyInteraction; a distance of 10 cm or less is a tap (`TapProximity`).
/// - **Every iPhone** (also the fallback when the other phone has no UWB): both phones feel the bump
///   with CoreMotion and tell each other over the link; bumps within 0.7 s of each other are a tap.
@MainActor
@Observable
final class ProximityTapDetector: TapDetecting {
    @ObservationIgnored let capability: TapCapability
    /// Observed: the Tap Phones page explains how to turn Nearby Interactions back on.
    private(set) var isNearbyInteractionDenied = false
    var canSimulate: Bool { false }

    @ObservationIgnored private let supportsUWB: Bool
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private weak var transport: (any NearbyTransport)?
    @ObservationIgnored private var ownToken: String?
    @ObservationIgnored private var output: AsyncStream<TapDetection>.Continuation?
    @ObservationIgnored private var motionTask: Task<Void, Never>?

    @ObservationIgnored private var tokens: [NearbyPeerHandle: String] = [:]
    @ObservationIgnored private var linked: Set<NearbyPeerHandle> = []
    @ObservationIgnored private var peerRangingTokens: [NearbyPeerHandle: NIDiscoveryToken] = [:]
    @ObservationIgnored private var rangers: [NearbyPeerHandle: NearbyInteractionRanger] = [:]
    @ObservationIgnored private var proximity: [NearbyPeerHandle: TapProximity] = [:]
    @ObservationIgnored private var bumpDetector = BumpDetector()
    @ObservationIgnored private var bumpMatcher = BumpMatcher<NearbyPeerHandle>()
    @ObservationIgnored private var lastDetections: [String: Date] = [:]

    init() {
        supportsUWB = NearbyInteractionRanger.isSupported
        if supportsUWB {
            capability = .preciseDistance
        } else if motion.isDeviceMotionAvailable {
            capability = .bump
        } else {
            capability = .unsupported
        }
    }

    private var isActive: Bool { output != nil }

    func start(using transport: any NearbyTransport, ownToken: String?) -> AsyncStream<TapDetection> {
        stop()
        self.transport = transport
        self.ownToken = ownToken
        let (stream, continuation) = AsyncStream.makeStream(of: TapDetection.self)
        output = continuation
        for peer in linked { greet(peer) }
        startMotion()
        return stream
    }

    func stop() {
        for ranger in rangers.values { ranger.invalidate() }
        rangers = [:]
        proximity = [:]
        motionTask?.cancel()
        motionTask = nil
        if motion.isDeviceMotionActive { motion.stopDeviceMotionUpdates() }
        output?.finish()
        output = nil
    }

    func simulateTap() {}

    // MARK: Transport events

    func handle(_ event: NearbyTransportEvent) {
        switch event {
        case .found(let peer, let token):
            tokens[peer] = token
        case .lost(let peer):
            tokens[peer] = nil
            forget(peer)
        case .linked(let peer):
            linked.insert(peer)
            if isActive { greet(peer) }
        case .unlinked(let peer):
            linked.remove(peer)
            forget(peer)
        case .received(let data, let peer):
            receive(data, from: peer)
        case .state:
            break
        }
    }

    private func receive(_ data: Data, from peer: NearbyPeerHandle) {
        switch TapMessage(data: data) {
        case .rangingToken(let tokenData):
            guard supportsUWB, let token = NearbyInteractionRanger.unarchive(tokenData) else { return }
            peerRangingTokens[peer] = token
            if isActive { ranger(for: peer).run(peerToken: token) }
        case .bump:
            guard isActive else { return }
            if bumpMatcher.recordPeerBump(from: peer, at: .now) { fire(peer, signal: .bump) }
        case nil:
            break
        }
    }

    // MARK: UWB

    /// Sends this phone's ranging token and starts ranging if the peer's token is already known.
    private func greet(_ peer: NearbyPeerHandle) {
        guard supportsUWB, !isNearbyInteractionDenied else { return }
        let ranger = ranger(for: peer)
        if let data = ranger.tokenData, let message = TapMessage.rangingToken(data).encoded {
            transport?.send(message, to: peer)
        }
        if let token = peerRangingTokens[peer] { ranger.run(peerToken: token) }
    }

    private func ranger(for peer: NearbyPeerHandle) -> NearbyInteractionRanger {
        if let existing = rangers[peer] { return existing }
        let ranger = NearbyInteractionRanger { [weak self] event in
            self?.ranging(event, from: peer)
        }
        rangers[peer] = ranger
        return ranger
    }

    private func ranging(_ event: RangingEvent, from peer: NearbyPeerHandle) {
        switch event {
        case .distance(let distance):
            if proximity[peer, default: TapProximity()].update(distance: distance) {
                fire(peer, signal: .distance)
            }
        case .peerGone:
            proximity[peer] = TapProximity()
        case .suspensionEnded:
            break
        case .invalidated(let userDenied):
            if userDenied { isNearbyInteractionDenied = true }
            rangers.removeValue(forKey: peer)?.invalidate()
        }
    }

    private func forget(_ peer: NearbyPeerHandle) {
        rangers.removeValue(forKey: peer)?.invalidate()
        proximity[peer] = nil
        peerRangingTokens[peer] = nil
    }

    // MARK: Bump

    private func startMotion() {
        guard motion.isDeviceMotionAvailable, motionTask == nil else { return }
        let samples = MotionSampler.userAccelerationMagnitudes(from: motion)
        motionTask = Task { [weak self] in
            for await magnitude in samples {
                guard let self else { return }
                if self.bumpDetector.process(magnitude: magnitude, at: .now) { self.bumped() }
            }
        }
    }

    private func bumped() {
        if let message = TapMessage.bump.encoded {
            for peer in linked { transport?.send(message, to: peer) }
        }
        for peer in bumpMatcher.recordOwnBump(at: .now) {
            fire(peer, signal: .bump)
        }
    }

    // MARK: Detection

    private func fire(_ peer: NearbyPeerHandle, signal: TapDetection.Signal) {
        guard let output, let token = tokens[peer] else { return }
        let now = Date.now
        if let last = lastDetections[token], now.timeIntervalSince(last) < TapHandshake.repeatInterval { return }
        lastDetections[token] = now
        output.yield(TapDetection(token: token, signal: signal,
                                  initiatesRequest: TapHandshake.initiatesRequest(ownToken: ownToken, peerToken: token)))
    }
}
