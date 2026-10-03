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
            ConnectList(model: model, cards: cards, profile: profiles.first,
                        activeEventName: activeEvents.first?.name, onShowQR: showQR)
                .navigationTitle(ConnectCopy.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarItems }
                .sheet(item: $model.presentedIncomingRequest) { request in
                    IncomingRequestSheet(request: request, sharedCardName: selectedCard?.name,
                                         isAccepting: model.machine.isAccepting,
                                         onAccept: model.acceptIncoming, onDecline: model.declineIncoming)
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
            model.cardsChanged(to: ids, requested: requestedCardID)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close", systemImage: "xmark", action: router.dismiss)
        }
        if !cards.isEmpty {
            ToolbarItem(placement: .bottomBar) {
                Button("Show My QR", systemImage: "qrcode", action: showQR)
                    .labelStyle(.titleAndIcon)
            }
        }
        if showsDebugMenu {
            ToolbarItem(placement: .primaryAction) {
                Menu("Simulate", systemImage: "ladybug") {
                    Button("Incoming Request", systemImage: "person.badge.plus", action: simulateIncomingRequest)
                }
            }
        }
    }

    // MARK: Actions

    private func attach() {
        model.attach(client: client, modelContext: modelContext, router: router, requestedCardID: requestedCardID)
    }

    private var selectedCard: Card? {
        cards.first { $0.id == model.selectedCardID } ?? cards.first
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
