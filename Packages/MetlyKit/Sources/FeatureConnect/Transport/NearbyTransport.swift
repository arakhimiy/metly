import Foundation

/// Transport-local identity of a nearby device. Random per CONNECT session — never personal data.
nonisolated struct NearbyPeerHandle: Hashable, Sendable, CustomStringConvertible {
    let rawValue: String
    init(_ rawValue: String) { self.rawValue = rawValue }
    var description: String { rawValue }
}

nonisolated enum NearbyTransportState: Equatable, Sendable {
    case idle
    /// Advertising and browsing.
    case searching
    /// The user turned off Local Network access for the app (Settings › Privacy › Local Network).
    case localNetworkDenied
    case failed(String)
}

nonisolated enum NearbyTransportEvent: Equatable, Sendable {
    case state(NearbyTransportState)
    /// A device advertising Metly Connect, with its opaque server discovery token.
    case found(NearbyPeerHandle, token: String)
    case lost(NearbyPeerHandle)
    /// A private data link to the device is open (Tap Phones uses it to swap NearbyInteraction tokens).
    case linked(NearbyPeerHandle)
    case unlinked(NearbyPeerHandle)
    case received(Data, from: NearbyPeerHandle)
}

/// Finds other people with CONNECT open nearby. Peers only ever exchange the server's opaque,
/// rotating `discoveryToken` (plus Tap Phones handshake blobs) — names and cards come from the
/// server via `MetlyClient.resolvePeers(tokens:)`, which also enforces "Show in Nearby" and blocks.
@MainActor
protocol NearbyTransport: AnyObject {
    /// Starts advertising `token` and browsing. Events arrive until `stop()` (which finishes the stream).
    func start(advertising token: String) -> AsyncStream<NearbyTransportEvent>
    func stop()
    /// Sends a small blob to a linked peer (no-op when not linked).
    func send(_ data: Data, to peer: NearbyPeerHandle)
    /// Whether `send` reaches real devices (the demo transport has no data link).
    var supportsLinks: Bool { get }
}

@MainActor
enum NearbyTransportFactory {
    /// Real MultipeerConnectivity when talking to a server; the demo world when running on the mock
    /// (simulator, previews, no backend yet) — real peers' tokens can't be resolved by the mock anyway.
    /// `-MetlyRealNearby` forces MultipeerConnectivity on the mock too.
    static func make(demoTokens: [String]) -> any NearbyTransport {
        let forceReal = ProcessInfo.processInfo.arguments.contains("-MetlyRealNearby")
        if demoTokens.isEmpty || forceReal {
            return MultipeerNearbyTransport()
        }
        return DemoNearbyTransport(tokens: demoTokens)
    }
}
