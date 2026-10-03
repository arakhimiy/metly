import Foundation

/// Simulator / mock-server stand-in for Tap Phones: there's no second phone, so "Simulate Tap"
/// taps the first person the demo transport found (this phone sends the request).
@MainActor
final class DemoTapDetector: TapDetecting {
    let capability: TapCapability = .preciseDistance
    let isNearbyInteractionDenied = false
    var canSimulate: Bool { true }

    private var tokens: [String] = []
    private var output: AsyncStream<TapDetection>.Continuation?

    init() {}

    func start(using transport: any NearbyTransport, ownToken: String?) -> AsyncStream<TapDetection> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: TapDetection.self)
        output = continuation
        return stream
    }

    func stop() {
        output?.finish()
        output = nil
    }

    func handle(_ event: NearbyTransportEvent) {
        switch event {
        case .found(_, let token):
            if !tokens.contains(token) { tokens.append(token) }
        default:
            break
        }
    }

    func simulateTap() {
        guard let output, let token = tokens.first else { return }
        output.yield(TapDetection(token: token, signal: .simulated, initiatesRequest: true))
    }
}
