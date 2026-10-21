import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// QR_FULLSCREEN (cover, SPEC §2.5.28 / §3.7): full brightness, screen kept awake, card chooser,
/// Offline QR. Done offers "Who did you just meet?" when the code was up for more than 2 s.
struct QRFullscreenScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase
    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    @State private var selectedCardID: UUID
    /// The Offline QR switch; nil = automatic (`QRCodeMode.defaultsToOffline`), else the user's choice.
    @State private var prefersOffline: Bool?
    @State private var shownAt = Date.now
    @State private var followUp: Presentation?
    @State private var isClosing = false
    @State private var brightness = ScreenBrightnessBoost()

    init(initialCardID: UUID) {
        _selectedCardID = State(initialValue: initialCardID)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let card = selectedCard {
                    QRFullscreenContent(card: card, cards: cards, profile: profiles.first,
                                        selectedCardID: $selectedCardID, prefersOffline: $prefersOffline,
                                        onConnect: connect, onShare: share)
                } else {
                    ContentUnavailableView("No Card to Show", systemImage: "qrcode",
                                           description: Text("Create a card to get your QR code."))
                }
            }
            .navigationTitle("QR Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Label("Brightness Raised", systemImage: "sun.max.fill")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: done)
                }
            }
        }
        .presentAfterDismiss($followUp)
        .onAppear(perform: brightness.activate)
        .onDisappear(perform: brightness.deactivate)
        .onChange(of: scenePhase) { _, phase in
            // Give the user's brightness back while the app is in the background.
            if phase == .active { brightness.activate() } else { brightness.deactivate() }
        }
        .onChange(of: services.network.isOnline) { _, isOnline in
            prefersOffline = QRCodeMode.preference(afterConnectivityChange: prefersOffline, isOnline: isOnline)
        }
        // The shown card was deleted (or a stale deep link named one): move the chooser to the
        // card that is actually on screen instead of keeping a dangling selection.
        .onChange(of: cards.map(\.id), initial: true) { _, ids in
            if let id = QRCardSelection.resolve(selectedCardID, among: ids), id != selectedCardID {
                selectedCardID = id
            }
        }
    }

    /// The chosen card, or the first one if it was deleted meanwhile.
    private var selectedCard: Card? {
        let id = QRCardSelection.resolve(selectedCardID, among: cards.map(\.id))
        return cards.first { $0.id == id }
    }

    private func done() {
        guard !isClosing else { return }
        isClosing = true
        if let card = selectedCard, JustMetPrompter.claimAfterQR(shownAt: shownAt, preferences: services.preferences) {
            followUp = .sheet(.justMet(cardID: card.id))
        }
        router.dismiss()
    }

    private func connect() {
        guard let card = selectedCard else { return }
        router.replaceTop(with: .cover(.connect(cardID: card.id)))
    }

    private func share() {
        guard let card = selectedCard else { return }
        router.present(.share(cardID: card.id))
    }
}
