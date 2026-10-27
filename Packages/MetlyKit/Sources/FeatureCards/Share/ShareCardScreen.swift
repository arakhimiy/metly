import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// SHARE_SHEET (sheet, SPEC §2.5.29, §9 Q33): card header, Copy Link, system share ("More…"),
/// Add to Apple Wallet, Save Image or PDF, and the global Pause All Links switch.
/// Closing it after a share action offers "Who did you just meet?" (rate-limited).
struct ShareCardScreen: View {
    let cardID: UUID

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Query(Card.live) private var cards: [Card]
    @Query(ProfileQuery.current) private var profiles: [Profile]

    /// Set by any share action (copy, system share, Wallet) — JUST_MET trigger B.
    @State private var didShare = false
    @State private var followUp: Presentation?

    var body: some View {
        // A single container (not Group), so onDisappear fires once for the sheet itself.
        ZStack {
            if let card = cards.first(where: { $0.id == cardID }) {
                ShareCardContent(card: card, profile: profiles.first, didShare: $didShare,
                                 onClose: close, onExport: openExport)
            } else {
                MissingCardView(title: String(localized: "Share"))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear(perform: didDisappear)
    }

    private func close() {
        router.dismiss()
    }

    /// "Save Image or PDF" → CARD_EXPORT once this sheet is gone.
    private func openExport() {
        followUp = .cover(.cardExport(cardID: cardID, tab: .image))
        router.dismiss()
    }

    /// Runs for Close, swipe-down and hand-offs alike.
    private func didDisappear() {
        if let next = followUp {
            followUp = nil
            router.presentRoute(next)
        } else if JustMetPrompter.claimAfterShare(didShare: didShare, preferences: services.preferences) {
            router.present(.justMet(cardID: cardID))
        }
    }
}
