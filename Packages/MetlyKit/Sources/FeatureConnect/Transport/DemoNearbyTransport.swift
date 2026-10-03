import Foundation

/// Simulator / mock-server stand-in: "discovers" the mock world's people (`client.demoNearbyTokens`)
/// one by one, so CONNECT is fully usable without real devices. Has no data link.
@MainActor
final class DemoNearbyTransport: NearbyTransport {
    private let tokens: [String]
    private let firstDelay: Duration
    private let interval: Duration
    private var task: Task<Void, Never>?
    private var continuation: AsyncStream<NearbyTransportEvent>.Continuation?

    init(tokens: [String], firstDelay: Duration = .milliseconds(1200), interval: Duration = .milliseconds(900)) {
        self.tokens = tokens
        self.firstDelay = firstDelay
        self.interval = interval
    }

    var supportsLinks: Bool { false }

    func start(advertising token: String) -> AsyncStream<NearbyTransportEvent> {
        stop()
        let (stream, continuation) = AsyncStream.makeStream(of: NearbyTransportEvent.self)
        self.continuation = continuation
        continuation.yield(.state(.searching))
        let tokens = tokens
        let firstDelay = firstDelay
        let interval = interval
        task = Task {
            for (index, token) in tokens.enumerated() {
                do {
                    try await Task.sleep(for: index == 0 ? firstDelay : interval)
                } catch {
                    return
                }
                continuation.yield(.found(NearbyPeerHandle("demo-\(index)"), token: token))
            }
        }
        return stream
    }

    func stop() {
        task?.cancel()
        task = nil
        continuation?.yield(.state(.idle))
        continuation?.finish()
        continuation = nil
    }

    func send(_ data: Data, to peer: NearbyPeerHandle) {}
}
