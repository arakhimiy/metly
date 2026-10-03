import Foundation

/// Detects Tap Phones gestures (two iPhones held top to top) for CONNECT's Tap Phones mode.
@MainActor
protocol TapDetecting: AnyObject {
    var capability: TapCapability { get }
    /// The user turned off Nearby Interactions for the app (UWB distance unavailable; bump still works).
    var isNearbyInteractionDenied: Bool { get }
    /// The demo world can fake a tap (no second phone in the simulator).
    var canSimulate: Bool { get }

    /// Starts watching; detections arrive until `stop()`.
    func start(using transport: any NearbyTransport, ownToken: String?) -> AsyncStream<TapDetection>
    func stop()
    /// Every transport event, also while stopped, so peers are known before Tap Phones opens.
    func handle(_ event: NearbyTransportEvent)
    func simulateTap()
}

@MainActor
enum TapDetectorFactory {
    static func make(for transport: any NearbyTransport) -> any TapDetecting {
        transport.supportsLinks ? ProximityTapDetector() : DemoTapDetector()
    }
}

/// Handshake blobs sent over the private MultipeerConnectivity link (never personal data).
nonisolated enum TapMessage: Codable, Equatable, Sendable {
    /// This phone's archived `NIDiscoveryToken` for UWB ranging.
    case rangingToken(Data)
    /// This phone just felt a bump.
    case bump

    var encoded: Data? { try? JSONEncoder().encode(self) }

    init?(data: Data) {
        guard let message = try? JSONDecoder().decode(TapMessage.self, from: data) else { return nil }
        self = message
    }
}
