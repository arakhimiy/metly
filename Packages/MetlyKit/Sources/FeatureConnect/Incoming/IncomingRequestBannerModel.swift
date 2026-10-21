import Foundation
import MetlyCore
import MetlyData
import MetlyNetworking
import Observation
import SwiftData

/// What the banner shows — a value copy, so a request the sync engine removes can't break the view.
struct IncomingRequestBannerItem: Equatable, Identifiable {
    let id: UUID
    let peerUserID: UUID
    let peerName: String
    /// "{title} · {company}".
    let role: String
    let eventName: String?
    let method: ConnectMethod

    init(_ request: ConnectRequest) {
        id = request.id
        peerUserID = request.peerUserID
        peerName = request.peerName
        role = [request.peerTitle, request.peerCompany].filter { !$0.isEmpty }.joined(separator: " · ")
        eventName = request.eventName.flatMap { $0.isEmpty ? nil : $0 }
        method = request.method
    }

    var firstName: String { ConnectCopy.firstName(of: peerName) }

    /// "{title} · {company}" and the event, on one line.
    var detail: String {
        [role, eventName ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

/// When the in-app banner tells the user about a connect request (pure rules, unit-tested).
enum IncomingRequestBannerPolicy {
    /// While CONNECT is open it shows live (Nearby / Tap Phones) requests itself as INCOMING_REQUEST.
    static func connectHandles(_ method: ConnectMethod, presentations: [Presentation]) -> Bool {
        guard method == .nearby || method == .tapPhones else { return false }
        return presentations.contains { presentation in
            if case .cover(.connect) = presentation { return true }
            return false
        }
    }

    /// The banner floats over the tabs and over "glanceable" modals only. Over screens with unsaved input
    /// (editors, capture forms) it waits until they close, so "View" never throws work away.
    static func canShow(over presentations: [Presentation]) -> Bool {
        presentations.allSatisfy(isGlanceable)
    }

    static func isGlanceable(_ presentation: Presentation) -> Bool {
        switch presentation {
        case .cover(.qr), .cover(.connect), .cover(.cardExport), .cover(.paywall), .cover(.eventEnded), .sheet(.share):
            true
        case .cover(.cardCreate), .cover(.cardEditor), .cover(.connected), .sheet(.startEvent), .sheet(.addContext),
             .sheet(.justMet), .sheet(.reminderEdit), .sheet(.eventExport):
            false
        }
    }

    /// Still worth answering: pending, not expired (live requests last 60 s), sender not blocked.
    static func isAnswerable(_ request: ConnectRequest, blockedUserIDs: Set<UUID>, now: Date) -> Bool {
        request.direction == .incoming && request.status == .pending && !request.isDeleted
            && !blockedUserIDs.contains(request.peerUserID)
            && (request.expiresAt.map { $0 > now } ?? true)
    }

    /// How long the banner stays up on its own (the request stays in People › Requests).
    static func displayDuration(expiresAt: Date?, now: Date) -> Duration {
        let standard: TimeInterval = 20
        guard let expiresAt else { return .seconds(standard) }
        return .seconds(max(0, min(standard, expiresAt.timeIntervalSince(now))))
    }
}

/// Requests that arrive while CONNECT is closed: one banner at a time, the rest queued (one per person).
/// Accept → CONNECTED (PLAN Q11), View → People › Requests, Later → stays in People › Requests.
@MainActor
@Observable
final class IncomingRequestBannerModel {
    private(set) var current: IncomingRequestBannerItem?
    private(set) var isAccepting = false
    /// Haptic / announcement trigger.
    private(set) var appearanceCount = 0

    @ObservationIgnored var now: () -> Date = { .now }
    /// Shows / hides the overlay window (driven from here, not from view updates: the root view doesn't
    /// update while a full-screen cover hides it).
    @ObservationIgnored var onVisibilityChange: (Bool) -> Void = { _ in }
    @ObservationIgnored private var client: MetlyClient?
    @ObservationIgnored private var modelContext: ModelContext?
    @ObservationIgnored private var router: AppRouter?
    @ObservationIgnored private var queue: [IncomingRequestBannerItem] = []
    /// Answered, viewed or put off — never shown again.
    @ObservationIgnored private var handled: Set<UUID> = []
    @ObservationIgnored nonisolated(unsafe) private var listenTask: Task<Void, Never>?

    init() {}

    deinit {
        listenTask?.cancel()
    }

    func attach(client: MetlyClient, modelContext: ModelContext, router: AppRouter) {
        self.client = client
        self.modelContext = modelContext
        self.router = router
    }

    /// Starts listening for requests and watching the modal stack, for as long as this model lives.
    /// Not tied to `.task`: the root's tasks are cancelled whenever a full-screen cover (e.g. the QR code)
    /// hides it — exactly when someone scans the code and sends a request.
    func start() {
        guard listenTask == nil, let client else { return }
        let events = client.events()
        listenTask = Task { [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        observeRouter()
    }

    private func handle(_ event: ConnectEvent) {
        switch event {
        case .requestReceived(let request):
            receive(request)
        case .requestUpdated, .shareBackReceived, .syncAvailable, .stateChanged:
            update()
        }
    }

    /// Re-checks the banner whenever a modal opens or closes, or the root phase changes.
    private func observeRouter() {
        guard let router else { return }
        withObservationTracking {
            _ = router.presentations
            _ = router.phase
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.update()
                self?.observeRouter()
            }
        }
    }

    func receive(_ dto: ConnectRequestDTO) {
        guard dto.direction == .incoming, dto.status == .pending, !handled.contains(dto.id),
              let router, router.phase == .main,
              let request = modelContext?.record(ConnectRequest.self, id: dto.id),
              !IncomingRequestBannerPolicy.connectHandles(request.method, presentations: router.presentations)
        else { return }
        let item = IncomingRequestBannerItem(request)
        guard current?.peerUserID != item.peerUserID else { return }   // already asking about this person
        queue.removeAll { $0.peerUserID == item.peerUserID }           // the newest request from a person wins
        queue.append(item)
        update()
    }

    /// Re-checks what's shown and queued (call when modals change or anything may have been answered).
    func update() {
        guard let router, let modelContext else { return }
        let blocked = ConnectModel.blockedUserIDs(in: modelContext)
        let presentations = router.presentations
        queue.removeAll { !isAnswerable($0, blocked: blocked) }

        if let shown = current, !isAccepting {
            if !isAnswerable(shown, blocked: blocked)
                || IncomingRequestBannerPolicy.connectHandles(shown.method, presentations: presentations) {
                setCurrent(nil)
            } else if !IncomingRequestBannerPolicy.canShow(over: presentations) {
                queue.insert(shown, at: 0)   // step aside while the user edits something; come back after
                setCurrent(nil)
            }
        }
        guard current == nil, !isAccepting, router.phase == .main,
              IncomingRequestBannerPolicy.canShow(over: presentations), !queue.isEmpty else { return }
        setCurrent(queue.removeFirst())
        appearanceCount += 1
    }

    /// "Later" (or the banner timed out / was swiped away): the request stays in People › Requests.
    func later() {
        guard let shown = current, !isAccepting else { return }
        handled.insert(shown.id)
        setCurrent(nil)
        update()
    }

    /// "View": People › Requests lists everything that's waiting.
    func view() {
        guard !isAccepting else { return }
        if let shown = current { handled.insert(shown.id) }
        handled.formUnion(queue.map(\.id))
        queue.removeAll()
        setCurrent(nil)
        router?.popToRoot(.people)
        router?.select(.people)
    }

    /// "Accept": shares the card to share and lands on CONNECTED to capture context (PLAN Q11).
    func accept() async {
        guard let shown = current, !isAccepting, let client, let modelContext, let router else { return }
        let blocked = ConnectModel.blockedUserIDs(in: modelContext)
        guard let request = modelContext.record(ConnectRequest.self, id: shown.id),
              IncomingRequestBannerPolicy.isAnswerable(request, blockedUserIDs: blocked, now: now()) else {
            finish(shown)
            router.showToast("This request has expired", systemImage: "clock.badge.xmark")
            update()
            return
        }
        guard let cardID = request.myCardID ?? modelContext.cardToShare()?.id else {
            router.showToast("Create a card first, then accept.", systemImage: "rectangle.stack.badge.plus")
            return
        }

        isAccepting = true
        do {
            let connection = try await client.accept(request, sharing: cardID)
            // Offline: the accept is queued; create the connection locally so CONNECTED can capture context.
            let accepted = connection ?? OfflineAccept.connection(for: request, sharing: cardID, in: modelContext)
            isAccepting = false
            finish(shown)
            let connected = Presentation.cover(.connected(connectionID: accepted.id))
            if case .cover(.connect)? = router.presentations.last {
                router.replaceTop(with: connected)
            } else {
                router.present(.connected(connectionID: accepted.id))
            }
        } catch {
            isAccepting = false
            finish(shown)
            router.showToast(error.localizedDescription, systemImage: "exclamationmark.triangle")
        }
        update()
    }

    // MARK: Private

    private func setCurrent(_ item: IncomingRequestBannerItem?) {
        let changed = item?.id != current?.id
        current = item
        if changed { onVisibilityChange(item != nil) }
    }

    private func finish(_ item: IncomingRequestBannerItem) {
        handled.insert(item.id)
        if current?.id == item.id { setCurrent(nil) }
    }

    private func isAnswerable(_ item: IncomingRequestBannerItem, blocked: Set<UUID>) -> Bool {
        guard !handled.contains(item.id), let request = modelContext?.record(ConnectRequest.self, id: item.id) else { return false }
        return IncomingRequestBannerPolicy.isAnswerable(request, blockedUserIDs: blocked, now: now())
    }
}
