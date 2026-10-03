import Foundation
@preconcurrency import MultipeerConnectivity
import Network

/// Nearby discovery over MultipeerConnectivity (PLAN Q7), Bonjour type `_metly-connect._tcp/_udp`
/// (declared in `NSBonjourServices`; the first start triggers the Local Network prompt).
///
/// - The advertised discovery info is only the server's opaque `discoveryToken`; the peer's display
///   name is a random string per session, never the user's name.
/// - Found peers are linked with an encrypted `MCSession` (the peer with the smaller display name
///   invites, so pairs don't invite each other twice). Tap Phones uses the link to swap
///   NearbyInteraction tokens and bump marks.
/// - Local Network denial is detected with `LocalNetworkWatcher` and reported as `.localNetworkDenied`.
@MainActor
final class MultipeerNearbyTransport: NearbyTransport {
    nonisolated static let serviceType = "metly-connect"
    nonisolated static let tokenKey = "t"
    private static let inviteTimeout: TimeInterval = 15
    private static let maxInviteAttempts = 3

    private let localPeer = MCPeerID(displayName: String(UUID().uuidString.replacing("-", with: "").prefix(16)))
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var proxy: MultipeerDelegateProxy?
    private var networkWatcher: NWBrowser?
    private var pump: Task<Void, Never>?
    private var output: AsyncStream<NearbyTransportEvent>.Continuation?

    private var peers: [NearbyPeerHandle: MCPeerID] = [:]
    private var linked: Set<NearbyPeerHandle> = []
    private var inviteAttempts: [NearbyPeerHandle: Int] = [:]
    private var state: NearbyTransportState = .idle

    init() {}

    var supportsLinks: Bool { true }

    func start(advertising token: String) -> AsyncStream<NearbyTransportEvent> {
        stop()
        let (stream, output) = AsyncStream.makeStream(of: NearbyTransportEvent.self)
        self.output = output

        let (callbacks, input) = AsyncStream.makeStream(of: MultipeerCallback.self)
        let session = MCSession(peer: localPeer, securityIdentity: nil, encryptionPreference: .required)
        let proxy = MultipeerDelegateProxy(session: session, continuation: input)
        session.delegate = proxy
        let advertiser = MCNearbyServiceAdvertiser(peer: localPeer, discoveryInfo: [Self.tokenKey: token],
                                                   serviceType: Self.serviceType)
        advertiser.delegate = proxy
        let browser = MCNearbyServiceBrowser(peer: localPeer, serviceType: Self.serviceType)
        browser.delegate = proxy

        self.session = session
        self.proxy = proxy
        self.advertiser = advertiser
        self.browser = browser

        pump = Task { [weak self] in
            for await callback in callbacks {
                guard let self else { return }
                self.handle(callback)
            }
        }
        networkWatcher = LocalNetworkWatcher.start(serviceType: "_\(Self.serviceType)._tcp") { denied in
            input.yield(.localNetwork(denied: denied))
        }

        advertiser.startAdvertisingPeer()
        browser.startBrowsingForPeers()
        update(.searching)
        return stream
    }

    func stop() {
        pump?.cancel()
        pump = nil
        advertiser?.stopAdvertisingPeer()
        advertiser?.delegate = nil
        browser?.stopBrowsingForPeers()
        browser?.delegate = nil
        session?.disconnect()
        session?.delegate = nil
        networkWatcher?.cancel()
        proxy?.finish()
        advertiser = nil
        browser = nil
        session = nil
        proxy = nil
        networkWatcher = nil
        peers = [:]
        linked = []
        inviteAttempts = [:]
        state = .idle
        output?.finish()
        output = nil
    }

    func send(_ data: Data, to peer: NearbyPeerHandle) {
        guard let session, linked.contains(peer), let peerID = peers[peer] else { return }
        try? session.send(data, toPeers: [peerID], with: .reliable)
    }

    // MARK: Callbacks

    private func handle(_ callback: MultipeerCallback) {
        switch callback {
        case .found(let ref, let token):
            guard let token, !token.isEmpty else { return }
            let handle = NearbyPeerHandle(ref.peer.displayName)
            peers[handle] = ref.peer
            output?.yield(.found(handle, token: token))
            inviteIfNeeded(handle)

        case .lost(let ref):
            let handle = NearbyPeerHandle(ref.peer.displayName)
            peers[handle] = nil
            inviteAttempts[handle] = nil
            output?.yield(.lost(handle))

        case .sessionState(let ref, let sessionState):
            let handle = NearbyPeerHandle(ref.peer.displayName)
            switch sessionState {
            case .connected:
                peers[handle] = peers[handle] ?? ref.peer
                if linked.insert(handle).inserted { output?.yield(.linked(handle)) }
            case .notConnected:
                if linked.remove(handle) != nil { output?.yield(.unlinked(handle)) }
                inviteIfNeeded(handle)
            case .connecting:
                break
            @unknown default:
                break
            }

        case .received(let data, let ref):
            output?.yield(.received(data, from: NearbyPeerHandle(ref.peer.displayName)))

        case .failed(let code, let message):
            update(LocalNetworkWatcher.isPolicyDenied(code: code) ? .localNetworkDenied : .failed(message))

        case .localNetwork(let denied):
            if denied {
                update(.localNetworkDenied)
            } else if state == .localNetworkDenied {
                // Access was turned back on in Settings: restart so MultipeerConnectivity picks it up.
                advertiser?.stopAdvertisingPeer()
                browser?.stopBrowsingForPeers()
                advertiser?.startAdvertisingPeer()
                browser?.startBrowsingForPeers()
                update(.searching)
            }
        }
    }

    /// The peer with the smaller display name invites; the other accepts (see the proxy).
    private func inviteIfNeeded(_ handle: NearbyPeerHandle) {
        guard let browser, let session, let peerID = peers[handle], !linked.contains(handle),
              localPeer.displayName < peerID.displayName,
              !session.connectedPeers.contains(peerID) else { return }
        let attempts = inviteAttempts[handle, default: 0]
        guard attempts < Self.maxInviteAttempts else { return }
        inviteAttempts[handle] = attempts + 1
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: Self.inviteTimeout)
    }

    private func update(_ newState: NearbyTransportState) {
        guard newState != state else { return }
        state = newState
        output?.yield(.state(newState))
    }
}
