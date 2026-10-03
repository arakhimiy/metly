import Foundation
import MetlyCore
import MetlyData

/// The CONNECT screen's request lifecycle as a pure state machine (SPEC §3.12, PLAN Q8/Q9/Q11).
///
/// ```
/// idle ──discoveryStarted──▶ discovering ──connectTapped──▶ waiting ──outcome──▶ connected | discovering (+ notice)
///                                 ▲                            │ cancelTapped
///                                 └────────────────────────────┘
/// incoming request (any phase but connected) ──acceptTapped──▶ accepting ──acceptSucceeded──▶ connected
/// ```
/// - One outgoing request at a time; Connect taps while waiting are ignored.
/// - The requester never learns about a decline: declined / expired / timed out all read as "No response".
/// - An incoming request can arrive while waiting; accepting it withdraws the outgoing request.
///
/// `send(_:)` returns the side effects the caller (`ConnectModel`) must run.
nonisolated struct ConnectMachine: Equatable, Sendable {
    /// The person a request goes to.
    struct Peer: Equatable, Hashable, Sendable {
        var userID: UUID
        var firstName: String
        /// Their current Nearby discovery token (the request target).
        var token: String
    }

    /// An incoming live request shown as INCOMING_REQUEST.
    struct Incoming: Equatable, Sendable {
        var requestID: UUID
        var peerUserID: UUID
        var firstName: String
    }

    enum Phase: Equatable, Sendable {
        /// Discovery isn't running (hidden from Nearby, permission denied, offline, starting up).
        case idle
        /// Advertising + browsing; the Nearby list is live.
        case discovering
        /// A request was sent; "Waiting…" until accepted / no response / cancelled.
        case waiting(Peer, method: ConnectMethod)
        /// Accepting an incoming request.
        case accepting(requestID: UUID)
        /// Both sides are connected → CONNECTED.
        case connected(connectionID: UUID)
    }

    enum Notice: Equatable, Sendable {
        /// "{first} didn't respond. Try again or show your QR." (declined, expired and timed out alike).
        case noResponse(firstName: String)
        /// A request couldn't be sent or accepted (offline, peer unavailable…).
        case failed(message: String)
    }

    enum Event: Equatable, Sendable {
        case discoveryStarted
        case discoveryStopped
        case connectTapped(Peer, method: ConnectMethod)
        case requestFailed(message: String)
        /// How the outgoing request to `peerUserID` ended.
        case outcome(ConnectOutcome, peerUserID: UUID)
        case cancelTapped
        case incomingReceived(Incoming)
        /// The INCOMING_REQUEST sheet was swiped away (the request stays in People › Requests).
        case incomingDismissed
        case acceptTapped
        case declineTapped
        case acceptSucceeded(connectionID: UUID)
        case acceptFailed(message: String)
        case noticeDismissed
    }

    enum Effect: Equatable, Sendable {
        case sendRequest(Peer, method: ConnectMethod)
        /// Stop waiting and withdraw the outgoing request on the server.
        case withdrawRequest
        case accept(requestID: UUID)
        case decline(requestID: UUID)
        /// `router.replaceTop(with: .cover(.connected(connectionID:)))`.
        case openConnected(connectionID: UUID)
    }

    private(set) var phase: Phase = .idle
    private(set) var notice: Notice?
    private(set) var incoming: Incoming?
    private(set) var isDiscoveryActive = false

    init() {}

    /// Restores a specific state (previews).
    init(phase: Phase, notice: Notice? = nil, incoming: Incoming? = nil, isDiscoveryActive: Bool = true) {
        self.phase = phase
        self.notice = notice
        self.incoming = incoming
        self.isDiscoveryActive = isDiscoveryActive
    }

    // MARK: Derived

    /// The peer we're waiting on, if any.
    var waitingPeer: Peer? {
        if case .waiting(let peer, _) = phase { return peer }
        return nil
    }

    var isWaiting: Bool { waitingPeer != nil }

    var isAccepting: Bool {
        if case .accepting = phase { return true }
        return false
    }

    var connectedID: UUID? {
        if case .connected(let id) = phase { return id }
        return nil
    }

    /// Connect buttons are enabled only while browsing with nothing outstanding.
    var canSendRequest: Bool { phase == .discovering }

    /// Where the machine rests when a request ends.
    private var restingPhase: Phase { isDiscoveryActive ? .discovering : .idle }

    // MARK: Transitions

    @discardableResult
    mutating func send(_ event: Event) -> [Effect] {
        switch event {
        case .discoveryStarted:
            isDiscoveryActive = true
            if phase == .idle { phase = .discovering }
            return []

        case .discoveryStopped:
            isDiscoveryActive = false
            if phase == .discovering { phase = .idle }
            return []

        case .connectTapped(let peer, let method):
            guard phase == .discovering else { return [] }
            notice = nil
            phase = .waiting(peer, method: method)
            return [.sendRequest(peer, method: method)]

        case .requestFailed(let message):
            guard isWaiting else { return [] }
            phase = restingPhase
            notice = .failed(message: message)
            return []

        case .outcome(let outcome, let peerUserID):
            return handle(outcome, from: peerUserID)

        case .cancelTapped:
            guard isWaiting else { return [] }
            phase = restingPhase
            return [.withdrawRequest]

        case .incomingReceived(let request):
            switch phase {
            case .accepting, .connected:
                return []
            case .idle, .discovering, .waiting:
                // Keep the one already on screen; later ones wait in People › Requests.
                if incoming == nil { incoming = request }
                return []
            }

        case .incomingDismissed:
            guard !isAccepting else { return [] }
            incoming = nil
            return []

        case .acceptTapped:
            guard let request = incoming, !isAccepting, connectedID == nil else { return [] }
            let wasWaiting = isWaiting
            notice = nil
            phase = .accepting(requestID: request.requestID)
            return wasWaiting ? [.withdrawRequest, .accept(requestID: request.requestID)] : [.accept(requestID: request.requestID)]

        case .declineTapped:
            guard let request = incoming, !isAccepting else { return [] }
            incoming = nil
            return [.decline(requestID: request.requestID)]

        case .acceptSucceeded(let connectionID):
            guard isAccepting else { return [] }
            incoming = nil
            phase = .connected(connectionID: connectionID)
            return [.openConnected(connectionID: connectionID)]

        case .acceptFailed(let message):
            guard isAccepting else { return [] }
            incoming = nil
            phase = restingPhase
            notice = .failed(message: message)
            return []

        case .noticeDismissed:
            notice = nil
            return []
        }
    }

    private mutating func handle(_ outcome: ConnectOutcome, from peerUserID: UUID) -> [Effect] {
        switch outcome {
        case .accepted(let connectionID):
            switch phase {
            case .waiting(let peer, _) where peer.userID == peerUserID:
                phase = .connected(connectionID: connectionID)
                notice = nil
                return [.openConnected(connectionID: connectionID)]
            case .discovering, .idle:
                // Accepted just as the user cancelled: the connection exists on both sides, so show it.
                phase = .connected(connectionID: connectionID)
                notice = nil
                return [.openConnected(connectionID: connectionID)]
            case .waiting, .accepting, .connected:
                return []
            }
        case .noResponse:
            guard let peer = waitingPeer, peer.userID == peerUserID else { return [] }
            phase = restingPhase
            notice = .noResponse(firstName: peer.firstName)
            return []
        case .cancelled:
            guard let peer = waitingPeer, peer.userID == peerUserID else { return [] }
            phase = restingPhase
            return []
        }
    }
}
