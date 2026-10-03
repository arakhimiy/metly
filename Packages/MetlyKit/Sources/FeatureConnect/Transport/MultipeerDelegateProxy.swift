import Foundation
@preconcurrency import MultipeerConnectivity

/// `MCPeerID` is immutable after creation, so sharing it across threads is safe; MultipeerConnectivity
/// just isn't annotated for Swift concurrency.
nonisolated struct PeerRef: @unchecked Sendable {
    let peer: MCPeerID
    init(_ peer: MCPeerID) { self.peer = peer }
}

/// What MultipeerConnectivity reported, already reduced to Sendable values.
nonisolated enum MultipeerCallback: Sendable {
    case found(PeerRef, token: String?)
    case lost(PeerRef)
    case sessionState(PeerRef, MCSessionState)
    case received(Data, from: PeerRef)
    case failed(code: Int, message: String)
    /// From the Local Network watcher: true = denied, false = allowed again.
    case localNetwork(denied: Bool)
}

/// MultipeerConnectivity calls its delegates on private queues. This proxy only turns callbacks into
/// `MultipeerCallback`s on an `AsyncStream` (keeping their order); `MultipeerNearbyTransport`
/// consumes them on the main actor.
nonisolated final class MultipeerDelegateProxy: NSObject, MCSessionDelegate, MCNearbyServiceAdvertiserDelegate, MCNearbyServiceBrowserDelegate {
    private let session: MCSession
    private let continuation: AsyncStream<MultipeerCallback>.Continuation

    init(session: MCSession, continuation: AsyncStream<MultipeerCallback>.Continuation) {
        self.session = session
        self.continuation = continuation
    }

    func finish() {
        continuation.finish()
    }

    // MARK: Advertiser

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                    withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // The link only carries Tap Phones handshake blobs (NearbyInteraction tokens, bump marks); the
        // session is encrypted and no personal data ever travels over it.
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        let error = error as NSError
        continuation.yield(.failed(code: error.code, message: error.localizedDescription))
    }

    // MARK: Browser

    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        continuation.yield(.found(PeerRef(peerID), token: info?[MultipeerNearbyTransport.tokenKey]))
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        continuation.yield(.lost(PeerRef(peerID)))
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        let error = error as NSError
        continuation.yield(.failed(code: error.code, message: error.localizedDescription))
    }

    // MARK: Session

    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        continuation.yield(.sessionState(PeerRef(peerID), state))
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        continuation.yield(.received(data, from: PeerRef(peerID)))
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        stream.close()   // Streams aren't part of the protocol.
    }

    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 with progress: Progress) {}

    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID,
                 at localURL: URL?, withError error: (any Error)?) {}
}
