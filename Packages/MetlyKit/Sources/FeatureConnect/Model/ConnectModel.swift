import Foundation
import MetlyCore
import MetlyData
import MetlyNetworking
import Observation
import SwiftData

/// Runs CONNECT: the server session, the Nearby transport, peer resolution, Tap Phones detection,
/// outgoing requests and INCOMING_REQUEST. Request logic lives in `ConnectMachine`; this class
/// performs its effects. The view drives lifetimes with `.task` (`runDiscovery`, `runTapDetection`,
/// `listenForIncoming`), so everything stops when CONNECT closes.
@MainActor
@Observable
final class ConnectModel {
    /// How long a lost peer stays listed (MultipeerConnectivity reports flaky lost/found pairs).
    static let lostGracePeriod: Duration = .seconds(4)
    /// "No One Nearby Yet" appears after this long without anyone.
    static let emptyStateDelay: Duration = .seconds(10)

    private(set) var machine: ConnectMachine
    private(set) var peers: NearbyPeerList
    private(set) var availability: ConnectAvailability
    private(set) var hasWaitedForPeers: Bool
    private(set) var tapStatus: TapStatus
    private(set) var tapCapability: TapCapability
    private(set) var canSimulateTap = false
    /// Bumped to restart discovery (Try Again, Show in Nearby turned on).
    private(set) var discoveryGeneration = 0
    /// Haptic triggers.
    private(set) var tapDetectionCount = 0
    private(set) var incomingCount = 0

    var mode: ConnectMode
    var selectedCardID: UUID?

    @ObservationIgnored private let isStatic: Bool
    @ObservationIgnored private let makeTransport: @MainActor ([String]) -> any NearbyTransport
    @ObservationIgnored private var client: MetlyClient?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var router: AppRouter?
    @ObservationIgnored private var transport: (any NearbyTransport)?
    @ObservationIgnored private var tapDetector: (any TapDetecting)?

    @ObservationIgnored private var currentRunID: UUID?
    @ObservationIgnored private var ownToken: String?
    @ObservationIgnored private var tokensByHandle: [NearbyPeerHandle: String] = [:]
    @ObservationIgnored private var pendingTokens: Set<String> = []
    @ObservationIgnored private var unresolvableTokens: Set<String> = []
    @ObservationIgnored private var deferredDrops: Set<String> = []
    @ObservationIgnored private var blockedUserIDs: Set<UUID> = []
    @ObservationIgnored private var knownRequests: [UUID: ConnectRequest] = [:]
    @ObservationIgnored private var resolveTask: Task<Void, Never>?
    @ObservationIgnored private var lostTasks: [NearbyPeerHandle: Task<Void, Never>] = [:]
    @ObservationIgnored private var outgoingTask: Task<Void, Never>?
    @ObservationIgnored private var outgoingRequest: ConnectRequestDTO?
    /// Requests the user cancelled; the peer may have accepted one just before the cancel reached the server.
    @ObservationIgnored private var withdrawnRequestIDs: Set<UUID> = []
    @ObservationIgnored private var receiveTimeout: Task<Void, Never>?

    init(mode: ConnectMode = .nearby,
         makeTransport: @escaping @MainActor ([String]) -> any NearbyTransport = NearbyTransportFactory.make(demoTokens:)) {
        self.mode = mode
        self.makeTransport = makeTransport
        isStatic = false
        machine = ConnectMachine()
        peers = NearbyPeerList()
        availability = .starting
        hasWaitedForPeers = false
        tapStatus = .ready
        tapCapability = .preciseDistance
    }

    /// A frozen state for previews: discovery never starts, buttons still talk to the (mock) client.
    init(previewMode mode: ConnectMode, machine: ConnectMachine, peers: [NearbyPerson] = [],
         availability: ConnectAvailability = .active, hasWaitedForPeers: Bool = false,
         tapStatus: TapStatus = .ready, tapCapability: TapCapability = .preciseDistance) {
        self.mode = mode
        makeTransport = NearbyTransportFactory.make(demoTokens:)
        isStatic = true
        self.machine = machine
        self.peers = NearbyPeerList(people: peers)
        self.availability = availability
        self.hasWaitedForPeers = hasWaitedForPeers
        self.tapStatus = tapStatus
        self.tapCapability = tapCapability
    }

    // MARK: Derived state

    var incomingRequest: ConnectRequest? {
        machine.incoming.flatMap { knownRequests[$0.requestID] }
    }

    /// Drives the INCOMING_REQUEST sheet: swiping it away dismisses the request (it stays in People › Requests).
    var presentedIncomingRequest: ConnectRequest? {
        get { incomingRequest }
        set { if newValue == nil { dismissIncoming() } }
    }

    /// "No One Nearby Yet" (Nearby only).
    var showsNoOneNearby: Bool {
        hasWaitedForPeers && peers.isEmpty && availability == .active && !machine.isWaiting
    }

    /// Nearby Interactions were denied (UWB distance off; the bump fallback still works).
    var isNearbyInteractionDenied: Bool {
        tapDetector?.isNearbyInteractionDenied ?? false
    }

    var isTapDetectionWanted: Bool {
        mode == .tapPhones && availability == .active && machine.isDiscoveryActive && tapCapability != .unsupported
    }

    // MARK: Setup

    /// Wires the environment in. Call once from the view (`.task`) before the run loops.
    func attach(client: MetlyClient, modelContext: ModelContext, router: AppRouter, requestedCardID: UUID?) {
        guard self.client == nil else { return }
        self.client = client
        self.modelContext = modelContext
        self.router = router
        if selectedCardID == nil {
            selectedCardID = CardChoice.initialCardID(requested: requestedCardID, in: modelContext)
        }
        blockedUserIDs = Self.blockedUserIDs(in: modelContext)
        guard !isStatic else { return }
        let transport = makeTransport(client.demoNearbyTokens)
        let detector = TapDetectorFactory.make(for: transport)
        self.transport = transport
        tapDetector = detector
        tapCapability = detector.capability
        canSimulateTap = detector.canSimulate
    }

    // MARK: Discovery

    /// Starts a Connect session, advertises its token and keeps the Nearby list live until cancelled.
    func runDiscovery() async {
        guard !isStatic, let client, let modelContext, let transport else { return }
        // A restart (Try Again) starts the new run before the old one has finished cleaning up.
        let runID = UUID()
        currentRunID = runID
        resetDiscovery()
        // A superseded run skips its own cleanup (below), so stop whatever it left advertising and browsing
        // now: a restart that fails before `transport.start` (offline, hidden) must not leave MPC running.
        transport.stop()
        tapDetector?.stop()
        guard modelContext.currentProfile()?.privacySettings.showInNearby ?? true else {
            availability = .hiddenFromNearby
            return
        }
        guard let cardID = selectedCardID else {
            availability = .failed(String(localized: "Create a card first, then connect with people nearby.", bundle: .appStrings))
            return
        }
        availability = .starting
        let session: ConnectSessionDTO
        do {
            session = try await client.startConnectSession(cardID: cardID, eventID: modelContext.activeEvent()?.id,
                                                           method: mode == .tapPhones ? .tapPhones : .nearby)
        } catch {
            guard !Task.isCancelled else { return }
            availability = Self.availability(for: error)
            return
        }
        let sessionID = session.sessionID
        guard !Task.isCancelled else {
            Task { await client.endConnectSession(sessionID) }
            return
        }

        ownToken = session.discoveryToken
        let events = transport.start(advertising: session.discoveryToken)
        availability = .active
        send(.discoveryStarted)

        await withDiscardingTaskGroup { group in
            group.addTask { await self.consume(events) }
            group.addTask { await self.waitForEmptyState() }
        }

        // CONNECT closed (or restarted): stop advertising and withdraw anything outstanding.
        guard currentRunID == runID else {
            Task { await client.endConnectSession(sessionID) }
            return
        }
        transport.stop()
        tapDetector?.stop()
        if machine.isWaiting { send(.cancelTapped) }
        send(.discoveryStopped)
        resetDiscovery()
        Task { await client.endConnectSession(sessionID) }
    }

    /// Cards were added / deleted while CONNECT is open: keep the choice valid.
    func cardsChanged(to liveCardIDs: [UUID], requested: UUID?) {
        selectedCardID = CardChoice.validated(selectedCardID, requested: requested,
                                              cardToShare: modelContext?.cardToShare()?.id, liveCardIDs: liveCardIDs)
    }

    /// Restarts discovery (Try Again).
    func retry() {
        discoveryGeneration += 1
    }

    /// "Show in Nearby" was off: turn it on (synced) and start discovering.
    func turnOnShowInNearby() {
        guard let profile = modelContext?.currentProfile() else { return }
        profile.privacySettings.showInNearby = true
        profile.markChanged()
        try? modelContext?.save()
        retry()
    }

    private func consume(_ events: AsyncStream<NearbyTransportEvent>) async {
        for await event in events {
            handle(event)
        }
    }

    private func waitForEmptyState() async {
        do {
            try await Task.sleep(for: Self.emptyStateDelay)
            hasWaitedForPeers = true
        } catch {}
    }

    private func handle(_ event: NearbyTransportEvent) {
        tapDetector?.handle(event)
        switch event {
        case .state(let state):
            switch state {
            case .searching: availability = .active
            case .localNetworkDenied: availability = .localNetworkDenied
            case .failed(let message): availability = .failed(message)
            case .idle: break
            }
        case .found(let handle, let token):
            lostTasks.removeValue(forKey: handle)?.cancel()
            tokensByHandle[handle] = token
            discovered(token)
        case .lost(let handle):
            guard let token = tokensByHandle[handle] else { return }
            lostTasks[handle]?.cancel()
            lostTasks[handle] = Task { [weak self] in
                do { try await Task.sleep(for: Self.lostGracePeriod) } catch { return }
                self?.drop(token, handle: handle)
            }
        case .linked, .unlinked, .received:
            break
        }
    }

    private func discovered(_ token: String) {
        guard token != ownToken, !unresolvableTokens.contains(token), !peers.contains(token: token) else { return }
        pendingTokens.insert(token)
        scheduleResolve()
    }

    private func drop(_ token: String, handle: NearbyPeerHandle) {
        lostTasks[handle] = nil
        tokensByHandle[handle] = nil
        guard !tokensByHandle.values.contains(token) else { return }
        pendingTokens.remove(token)
        if let waiting = machine.waitingPeer, peers.person(withToken: token)?.userID == waiting.userID {
            deferredDrops.insert(token)   // keep the "Waiting…" row until the request ends
            return
        }
        peers.remove(token: token)
    }

    private func scheduleResolve() {
        guard resolveTask == nil else { return }
        resolveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            await self?.resolvePending()
        }
    }

    private func resolvePending() async {
        guard let client else { return }
        let batch = pendingTokens
        pendingTokens = []
        if !batch.isEmpty {
            do {
                let resolved = try await client.resolvePeers(tokens: batch.sorted())
                let live = Set(tokensByHandle.values)
                unresolvableTokens.formUnion(batch.subtracting(resolved.map(\.token)))
                blockedUserIDs = modelContext.map(Self.blockedUserIDs(in:)) ?? blockedUserIDs
                peers.merge(resolved.filter { live.contains($0.token) }, blocked: blockedUserIDs, ownToken: ownToken)
            } catch {
                guard !Task.isCancelled else { return }
                pendingTokens.formUnion(batch)
                try? await Task.sleep(for: .seconds(3))
            }
        }
        resolveTask = nil
        if !pendingTokens.isEmpty, !Task.isCancelled { scheduleResolve() }
    }

    /// Resolves one token right away (Tap Phones detected someone not listed yet).
    private func resolveNow(_ token: String) async -> NearbyPerson? {
        if let person = peers.person(withToken: token) { return person }
        guard let client, let resolved = try? await client.resolvePeers(tokens: [token]) else { return nil }
        peers.merge(resolved, blocked: blockedUserIDs, ownToken: ownToken)
        return peers.person(withToken: token)
    }

    private func resetDiscovery() {
        resolveTask?.cancel()
        resolveTask = nil
        for task in lostTasks.values { task.cancel() }
        lostTasks = [:]
        receiveTimeout?.cancel()
        receiveTimeout = nil
        tokensByHandle = [:]
        pendingTokens = []
        unresolvableTokens = []
        deferredDrops = []
        ownToken = nil
        peers = NearbyPeerList()
        hasWaitedForPeers = false
        tapStatus = .ready
    }

    // MARK: Tap Phones

    func runTapDetection() async {
        guard !isStatic, let transport, let tapDetector else { return }
        let detections = tapDetector.start(using: transport, ownToken: ownToken)
        for await detection in detections {
            await handleTap(detection)
        }
        tapDetector.stop()
    }

    func simulateTap() {
        tapDetector?.simulateTap()
    }

    private func handleTap(_ detection: TapDetection) async {
        guard machine.canSendRequest, tapStatus == .ready else { return }
        tapDetectionCount += 1
        guard let person = await resolveNow(detection.token), machine.canSendRequest else { return }
        if detection.initiatesRequest {
            tapStatus = .detected(person)
            connect(to: person, method: .tapPhones)
        } else {
            tapStatus = .receiving(person)
            receiveTimeout?.cancel()
            receiveTimeout = Task { [weak self] in
                do { try await Task.sleep(for: TapHandshake.receiveTimeout) } catch { return }
                guard let self, case .receiving(let waiting) = self.tapStatus, waiting.userID == person.userID else { return }
                self.tapStatus = .ready
            }
        }
    }

    // MARK: Requests

    func connect(to person: NearbyPerson, method: ConnectMethod = .nearby) {
        send(.connectTapped(person.asPeer, method: method))
    }

    func cancelRequest() {
        send(.cancelTapped)
    }

    func dismissNotice() {
        send(.noticeDismissed)
    }

    func acceptIncoming() {
        send(.acceptTapped)
    }

    func declineIncoming() {
        send(.declineTapped)
    }

    func dismissIncoming() {
        send(.incomingDismissed)
    }

    /// Listens for live requests while CONNECT is open (INCOMING_REQUEST), and for answers to requests
    /// the user cancelled a moment too late.
    func listenForIncoming() async {
        guard let client else { return }
        for await event in client.events() {
            switch event {
            case .requestReceived(let request):
                receive(request)
            case .requestUpdated(let request, let connection):
                withdrawnRequestUpdated(request, connection: connection)
            case .shareBackReceived, .syncAvailable, .stateChanged:
                break
            }
        }
    }

    /// The peer accepted just as the user tapped Cancel: the server can't withdraw an accepted request, so
    /// both sides are connected — show CONNECTED instead of silently adding them to People.
    func withdrawnRequestUpdated(_ request: ConnectRequestDTO, connection: ConnectionDTO?) {
        guard withdrawnRequestIDs.contains(request.id), request.status != .pending else { return }
        withdrawnRequestIDs.remove(request.id)
        guard request.status == .accepted, let modelContext else { return }
        let peerID = request.peer.userID
        var descriptor = FetchDescriptor<Connection>(predicate: #Predicate { $0.remoteUserID == peerID && $0.deletedAt == nil })
        descriptor.fetchLimit = 1
        guard let connectionID = connection?.id ?? (try? modelContext.fetch(descriptor).first)?.id else { return }
        send(.outcome(.accepted(connectionID: connectionID), peerUserID: peerID))
    }

    private func receive(_ dto: ConnectRequestDTO) {
        // Live methods only; scan / email requests wait in People › Requests.
        guard let modelContext, dto.direction == .incoming, dto.status == .pending,
              dto.method == .nearby || dto.method == .tapPhones,
              let request = modelContext.record(ConnectRequest.self, id: dto.id) else { return }
        blockedUserIDs = Self.blockedUserIDs(in: modelContext)
        present(request)
    }

    /// Shows INCOMING_REQUEST for a pending incoming request (unless its sender is blocked).
    func present(_ request: ConnectRequest) {
        guard request.direction == .incoming, request.status == .pending,
              !blockedUserIDs.contains(request.peerUserID) else { return }
        knownRequests[request.id] = request
        send(.incomingReceived(ConnectMachine.Incoming(requestID: request.id, peerUserID: request.peerUserID,
                                                       firstName: ConnectCopy.firstName(of: request.peerName))))
        guard machine.incoming?.requestID == request.id else { return }
        incomingCount += 1
        if case .receiving = tapStatus {
            receiveTimeout?.cancel()
            tapStatus = .ready
        }
    }

    // MARK: Effects

    private func send(_ event: ConnectMachine.Event) {
        let effects = machine.send(event)
        if !machine.isWaiting {
            if case .detected = tapStatus { tapStatus = .ready }
            flushDeferredDrops()
        }
        for effect in effects { run(effect) }
    }

    private func run(_ effect: ConnectMachine.Effect) {
        switch effect {
        case .sendRequest(let peer, let method): sendRequest(to: peer, method: method)
        case .withdrawRequest: withdrawOutgoing()
        case .accept(let requestID): accept(requestID: requestID)
        case .decline(let requestID): decline(requestID: requestID)
        case .openConnected(let connectionID): router?.replaceTop(with: .cover(.connected(connectionID: connectionID)))
        }
    }

    private func sendRequest(to peer: ConnectMachine.Peer, method: ConnectMethod) {
        guard let client, let cardID = selectedCardID else {
            send(.requestFailed(message: String(localized: "Choose a card to share first.", bundle: .appStrings)))
            return
        }
        outgoingTask?.cancel()
        outgoingTask = Task { [weak self] in
            do {
                let request = try await client.sendConnectRequest(to: .nearbyToken(peer.token), cardID: cardID, method: method)
                guard !Task.isCancelled else {
                    self?.withdrawnRequestIDs.insert(request.id)
                    Task { await client.cancel(request) }   // cancelled while sending: withdraw it
                    return
                }
                self?.outgoingRequest = request
                let outcome = await client.outcome(of: request)
                guard let self, !Task.isCancelled else { return }
                self.outgoingRequest = nil
                self.send(.outcome(outcome, peerUserID: peer.userID))
            } catch {
                guard let self, !Task.isCancelled else { return }
                self.send(.requestFailed(message: error.localizedDescription))
            }
        }
    }

    private func withdrawOutgoing() {
        outgoingTask?.cancel()
        outgoingTask = nil
        if let request = outgoingRequest, let client {
            outgoingRequest = nil
            withdrawnRequestIDs.insert(request.id)
            Task { await client.cancel(request) }
        }
    }

    private func accept(requestID: UUID) {
        guard let client, let modelContext, let request = knownRequests[requestID] else {
            send(.acceptFailed(message: String(localized: "This request is no longer available.", bundle: .appStrings)))
            return
        }
        guard let cardID = selectedCardID ?? modelContext.cardToShare()?.id else {
            send(.acceptFailed(message: String(localized: "Create a card first, then accept.", bundle: .appStrings)))
            return
        }
        Task { [weak self] in
            do {
                let connection = try await client.accept(request, sharing: cardID)
                // Offline: the accept is queued; create the connection locally so CONNECTED can capture context.
                let accepted = connection ?? OfflineAccept.connection(for: request, sharing: cardID, in: modelContext)
                self?.send(.acceptSucceeded(connectionID: accepted.id))
            } catch {
                self?.send(.acceptFailed(message: error.localizedDescription))
            }
        }
    }

    private func decline(requestID: UUID) {
        guard let client, let request = knownRequests[requestID] else { return }
        Task { try? await client.decline(request) }
        router?.showToast(String(localized: "Request Declined", bundle: .appStrings), systemImage: "xmark.circle")
    }

    private func flushDeferredDrops() {
        guard !deferredDrops.isEmpty else { return }
        let live = Set(tokensByHandle.values)
        for token in deferredDrops where !live.contains(token) {
            peers.remove(token: token)
        }
        deferredDrops = []
    }

    // MARK: Helpers

    static func blockedUserIDs(in modelContext: ModelContext) -> Set<UUID> {
        let descriptor = FetchDescriptor<Connection>(predicate: #Predicate { $0.isBlocked && $0.deletedAt == nil })
        let blocked = (try? modelContext.fetch(descriptor)) ?? []
        return Set(blocked.compactMap(\.remoteUserID))
    }

    static func availability(for error: any Error) -> ConnectAvailability {
        if let error = error as? APIError, case .offline = error { return .offline }
        return .failed(error.localizedDescription)
    }
}
