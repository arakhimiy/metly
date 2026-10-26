import Foundation
@preconcurrency import NearbyInteraction

/// What an `NISession` reported, reduced to Sendable values.
nonisolated enum RangingEvent: Sendable {
    case distance(Float?)
    case peerGone
    case suspensionEnded
    case invalidated(userDenied: Bool)
}

/// Forwards `NISessionDelegate` callbacks (delivered on a private queue) to an `AsyncStream`.
nonisolated final class RangingDelegateProxy: NSObject, NISessionDelegate {
    private let continuation: AsyncStream<RangingEvent>.Continuation

    init(continuation: AsyncStream<RangingEvent>.Continuation) {
        self.continuation = continuation
    }

    func finish() {
        continuation.finish()
    }

    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        let closest = nearbyObjects.compactMap(\.distance).min()
        continuation.yield(.distance(closest))
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        continuation.yield(.peerGone)
    }

    func sessionSuspensionEnded(_ session: NISession) {
        continuation.yield(.suspensionEnded)
    }

    func session(_ session: NISession, didInvalidateWith error: any Error) {
        let denied = (error as? NIError)?.code == .userDidNotAllow
        continuation.yield(.invalidated(userDenied: denied))
    }
}

/// UWB ranging with one peer (one `NISession` per peer). The first `run` shows the
/// Nearby Interaction permission prompt (`NSNearbyInteractionUsageDescription`).
@MainActor
final class NearbyInteractionRanger {
    private let session = NISession()
    private let proxy: RangingDelegateProxy
    private var pump: Task<Void, Never>?

    init(onEvent: @escaping @MainActor (RangingEvent) -> Void) {
        let (events, continuation) = AsyncStream.makeStream(of: RangingEvent.self, bufferingPolicy: .bufferingNewest(16))
        proxy = RangingDelegateProxy(continuation: continuation)
        session.delegate = proxy
        session.delegateQueue = DispatchQueue(label: "app.tanishly.ios.connect.ranging")
        pump = Task { [session] in
            for await event in events {
                if case .suspensionEnded = event, let configuration = session.configuration {
                    session.run(configuration)
                }
                onEvent(event)
            }
        }
    }

    /// This phone's token for this session, archived for the link.
    var tokenData: Data? {
        session.discoveryToken.flatMap(Self.archive)
    }

    func run(peerToken: NIDiscoveryToken) {
        session.run(NINearbyPeerConfiguration(peerToken: peerToken))
    }

    func invalidate() {
        session.invalidate()
        proxy.finish()
        pump?.cancel()
        pump = nil
    }

    nonisolated static var isSupported: Bool {
        NISession.deviceCapabilities.supportsPreciseDistanceMeasurement
    }

    nonisolated static func archive(_ token: NIDiscoveryToken) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
    }

    nonisolated static func unarchive(_ data: Data) -> NIDiscoveryToken? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data)
    }
}
