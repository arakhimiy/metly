import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftData
import SwiftUI

/// CARD_CREATE (cover wizard, SPEC §2.5.23 / §3.4): method → (template gallery → style) → details →
/// "Your Card Is Live". Template or Blank only in v1 (no AI designs).
///
/// - Free plan: blocked beyond 2 cards (ALERT_CARD_LIMIT → paywall).
/// - Origin `.setup` with no card yet: the first card can't be cancelled (every account keeps ≥ 1 card).
struct CardCreateScreen: View {
    let origin: CardCreateOrigin

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    @State private var path: [CreateStep] = []
    @State private var design = CardDesign()
    @State private var name = ""
    @State private var createdCardID: UUID?
    @State private var createdOffline = false
    @State private var hasPrepared = false
    @State private var isShowingLimitAlert = false
    @State private var followUp: Presentation?

    /// - Parameter initialPath: steps already pushed (previews start mid-wizard).
    init(origin: CardCreateOrigin, initialPath: [CreateStep] = []) {
        self.origin = origin
        _path = State(initialValue: initialPath)
    }

    var body: some View {
        Group {
            if let card = createdCard {
                CreateSuccessView(card: card, profile: profiles.first, createdOffline: createdOffline,
                                  onShare: shareNow, onDone: done)
                    .transition(.opacity)
            } else {
                NavigationStack(path: $path) {
                    CreateMethodStep(canCancel: canCancel, onCancel: router.dismiss, onChoose: choose)
                        .navigationDestination(for: CreateStep.self, destination: step)
                }
            }
        }
        .presentAfterDismiss($followUp)
        .onAppear(perform: prepare)
        .alert("Card Limit Reached", isPresented: $isShowingLimitAlert) {
            Button("Not Now", role: .cancel, action: router.dismiss)
            Button("See Pro", action: showLimitPaywall)
        } message: {
            Text("The Free plan includes 2 cards. Delete one, or upgrade to \(Brand.proName) for unlimited cards.")
        }
    }

    // MARK: Steps

    @ViewBuilder
    private func step(_ step: CreateStep) -> some View {
        switch step {
        case .gallery:
            CreateGalleryStep(design: $design, content: previewContent, allowsPro: allowsPro,
                              onRequirePro: showPaywall, onContinue: { path.append(.style) })
        case .style:
            CreateStyleStep(design: $design, content: previewContent, allowsPro: allowsPro,
                            onRequirePro: showPaywall, onContinue: { path.append(.details) })
        case .details:
            CreateDetailsStep(design: $design, name: $name, content: previewContent,
                              fields: profiles.first?.contactFields ?? ContactField.defaults, onPublish: publish)
        }
    }

    // MARK: State

    private var createdCard: Card? {
        guard let createdCardID else { return nil }
        return cards.first { $0.id == createdCardID }
    }

    private var canCancel: Bool { !(origin == .setup && cards.isEmpty) }

    private var allowsPro: Bool { services.entitlements.limits.allowsProTemplates }

    private var canCreate: Bool {
        CardManagement.canCreateCard(existingCount: cards.count, limits: services.entitlements.limits)
    }

    /// In-app preview with the user's own details (Public + Connections).
    private var previewContent: CardFaceContent {
        CardContentFactory.content(profile: profiles.first, design: design, audience: .connections, qrPayload: "")
    }

    // MARK: Actions

    private func prepare() {
        guard !hasPrepared else { return }
        hasPrepared = true
        name = CardNaming.defaultName(existing: cards.map(\.name))
        if !canCreate { isShowingLimitAlert = true }
    }

    private func choose(_ method: CreateMethod) {
        switch method {
        case .template:
            path = [.gallery]
        case .blank:
            design = CardDesign()   // minimal template, SPEC §3.4 defaults
            path = [.details]
        }
    }

    private func publish() {
        guard canCreate else {
            isShowingLimitAlert = true
            return
        }
        let card = CardLibrary.create(name: name, design: design, in: modelContext)
        try? modelContext.save()
        services.preferences.activeCardID = card.id   // the new card becomes the active one
        services.sync.requestSync()
        createdOffline = !services.network.isOnline
        withAnimation { createdCardID = card.id }
    }

    private func shareNow() {
        guard let createdCardID else { return }
        followUp = .sheet(.share(cardID: createdCardID))
        router.dismiss()
    }

    private func done() {
        let isLive = createdCard?.url != nil
        router.dismiss()
        router.showToast(isLive ? "Card Published" : "Card Saved", systemImage: "checkmark.circle")
    }

    private func showPaywall(_ trigger: PaywallTrigger) {
        router.present(.paywall(trigger: trigger))
    }

    private func showLimitPaywall() {
        router.replaceTop(with: .cover(.paywall(trigger: .cardLimit)))
    }
}
