import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// CONNECT (SPEC §2.5.26, §3.12): Nearby | Tap Phones, the card to share, live requests and
/// INCOMING_REQUEST. Presented as a cover with its own NavigationStack.
struct ConnectScreen: View {
    let requestedCardID: UUID?
    @State private var model: ConnectModel

    @Environment(AppRouter.self) private var router
    @Environment(MetlyClient.self) private var client
    @Environment(\.modelContext) private var modelContext
    @Query(Card.live) private var cards: [Card]
    @Query(Event.active) private var activeEvents: [Event]
    @Query private var profiles: [Profile]

    init(requestedCardID: UUID?, model: ConnectModel = ConnectModel()) {
        self.requestedCardID = requestedCardID
        _model = State(initialValue: model)
        _profiles = Query(FetchDescriptor<Profile>(predicate: #Predicate { $0.deletedAt == nil }))
    }

    var body: some View {
        NavigationStack {
            list
                .navigationTitle(ConnectCopy.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .sheet(item: incomingBinding) { request in
                    incomingSheet(for: request)
                }
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: model.tapDetectionCount)
        .sensoryFeedback(.impact(weight: .medium), trigger: model.incomingCount)
        .sensoryFeedback(trigger: model.machine.notice) { _, notice in
            notice.map { _ in SensoryFeedback.warning }
        }
        .task {
            attach()
            await model.listenForIncoming()
        }
        .task(id: model.discoveryGeneration) {
            attach()
            await model.runDiscovery()
        }
        .task(id: model.isTapDetectionWanted) {
            guard model.isTapDetectionWanted else { return }
            await model.runTapDetection()
        }
        .onChange(of: cards.map(\.id)) { _, ids in
            model.selectedCardID = CardChoice.validated(model.selectedCardID, requested: requestedCardID,
                                                        cardToShare: modelContext.cardToShare()?.id, liveCardIDs: ids)
        }
    }

    private var list: some View {
        @Bindable var model = model
        return List {
            Section {
                Picker("Mode", selection: $model.mode) {
                    ForEach(ConnectMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if let event = activeEvents.first {
                    EventPill(name: event.name)
                        .frame(maxWidth: .infinity)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            modeSections

            if !cards.isEmpty {
                CardChooserSection(cards: cards, profile: profiles.first, selection: $model.selectedCardID,
                                   isLocked: model.machine.isWaiting || model.machine.isAccepting)
            }
        }
        .listStyle(.insetGrouped)
        .animation(.default, value: model.peers)
        .animation(.default, value: model.machine)
    }

    @ViewBuilder
    private var modeSections: some View {
        if let reason = unavailableReason {
            Section {
                ConnectUnavailableView(reason: reason, onShowQR: { showQR() },
                                       onTurnOnNearby: { model.turnOnShowInNearby() },
                                       onRetry: { model.retry() })
            }
        } else {
            if let notice = model.machine.notice {
                Section {
                    ConnectNoticeRow(notice: notice, onShowQR: noticeQRAction(for: notice),
                                     onDismiss: { model.dismissNotice() })
                }
            }
            switch model.mode {
            case .nearby:
                NearbySections(model: model, onShowQR: { showQR() })
            case .tapPhones:
                TapPhonesSections(model: model, onUseNearby: { model.mode = .nearby })
            }
        }
    }

    private func incomingSheet(for request: ConnectRequest) -> some View {
        IncomingRequestSheet(request: request, sharedCardName: selectedCard?.name,
                             isAccepting: model.machine.isAccepting,
                             onAccept: { model.acceptIncoming() },
                             onDecline: { model.declineIncoming() })
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark") {
                router.dismiss()
            }
        }
        if !cards.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button("Show My QR", systemImage: "qrcode") {
                    showQR()
                }
                .labelStyle(.titleAndIcon)
            }
        }
        if showsDebugMenu {
            ToolbarItem(placement: .primaryAction) {
                Menu("Simulate", systemImage: "ladybug") {
                    Button("Incoming Request", systemImage: "person.badge.plus") {
                        simulateIncomingRequest()
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private func attach() {
        model.attach(client: client, modelContext: modelContext, router: router, requestedCardID: requestedCardID)
    }

    private var selectedCard: Card? {
        cards.first { $0.id == model.selectedCardID } ?? cards.first
    }

    private var unavailableReason: ConnectUnavailableView.Reason? {
        switch model.availability {
        case .starting, .active: nil
        case .hiddenFromNearby: .hiddenFromNearby
        case .localNetworkDenied: .localNetworkDenied
        case .offline: .offline
        case .failed(let message): .failed(message)
        }
    }

    private var incomingBinding: Binding<ConnectRequest?> {
        Binding {
            model.incomingRequest
        } set: { request in
            if request == nil { model.dismissIncoming() }
        }
    }

    /// "Show My QR" only makes sense in the no-response notice.
    private func noticeQRAction(for notice: ConnectMachine.Notice) -> (() -> Void)? {
        guard case .noResponse = notice else { return nil }
        return { showQR() }
    }

    private func showQR() {
        guard let card = selectedCard else { return }
        router.replaceTop(with: .cover(.qr(cardID: card.id)))
    }

    /// DEBUG builds on the mock server get a "Simulate" menu (no second phone in the simulator).
    private var showsDebugMenu: Bool {
        #if DEBUG
        client.isMock
        #else
        false
        #endif
    }

    /// Mock only: "Bekzod wants to connect" (drives INCOMING_REQUEST in the simulator and previews).
    private func simulateIncomingRequest() {
        #if DEBUG
        guard let server = client.mockServer else { return }
        let method: ConnectMethod = model.mode == .tapPhones ? .tapPhones : .nearby
        client.startRealtime()   // already running in the app; previews start it here
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            await server.simulateIncomingRequest(method: method)
        }
        #endif
    }
}
