import MetlyCore
import MetlyData
import MetlyDesign
import MetlySharedUI
import SwiftData
import SwiftUI

/// HOME tab root (SPEC §2.5.7): offline banner · active event · My Cards · Follow Up Today · Recent.
/// The card leads (shown every day). The event block appears only while an event runs (on top);
/// starting one lives in People's "+" menu and the Events filter.
struct HomeScreen: View {
    @Environment(AppServices.self) private var services
    @Environment(AppRouter.self) private var router

    @Query(filter: #Predicate<Profile> { $0.deletedAt == nil }) private var profiles: [Profile]
    @Query(Card.live) private var cards: [Card]
    @Query(FollowUp.open) private var openFollowUps: [FollowUp]
    @Query(Connection.live) private var connections: [Connection]
    @Query(Event.active) private var activeEvents: [Event]
    @State private var clock = DayClock()

    var body: some View {
        let profile = profiles.first
        let now = clock.now
        let calendar = Calendar.current
        let reminders = openFollowUps.filter { $0.connection?.isDeleted != true }
        let due = HomeSelection.dueToday(reminders, now: now, calendar: calendar)
        let todayState = FollowUpTodayState.make(dueCount: due.count,
                                                 upcoming: HomeSelection.upcomingCount(reminders, now: now, calendar: calendar))

        List {
            if !services.network.isOnline {
                OfflineBannerSection()
            }
            if let event = activeEvents.first {
                HomeEventSection(event: event)
            }
            MyCardsSection(profile: profile, cards: cards)
            FollowUpTodaySection(followUps: Array(due.prefix(HomeSelection.followUpLimit)), state: todayState, now: now)
            if connections.isEmpty {
                GetStartedSection()
            } else {
                RecentSection(people: HomeSelection.recent(connections), now: now)
            }
        }
        .listStyle(.insetGrouped)
        .contentMargins(.top, 8, for: .scrollContent)
        .tracksDayChanges($clock)   // "Follow Up Today" rolls over at midnight / when back in the foreground
        // No visible title: the bar holds only the avatar and the card actions, and the card leads the
        // screen. "Home" stays as the title for VoiceOver and the back button of pushed screens.
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Color.clear.frame(width: 1, height: 1).accessibilityHidden(true) }
            toolbarContent(profile: profile)
        }
        .refreshable { await services.sync.syncNow() }
    }

    /// Avatar (→ Profile tab) on the left; Show QR and Share for the carousel's card on the right, each in
    /// its own glass circle (iOS 26). No item may fall into the bar's "…" overflow.
    @ToolbarContentBuilder
    private func toolbarContent(profile: Profile?) -> some ToolbarContent {
        let card = activeCard(profile: profile)
        if #available(iOS 26, *) {
            ToolbarItem(placement: .topBarLeading) {
                ProfileAvatarButton(profile: profile) { router.select(.profile) }
            }
            .sharedBackgroundVisibility(.hidden)   // the button draws its own circular glass
            if let card {
                ToolbarItem(placement: .topBarTrailing) { showQRButton(card) }
                ToolbarSpacer(.fixed, placement: .topBarTrailing)   // separate glass for each action
                ToolbarItem(placement: .topBarTrailing) { shareButton(card) }
            }
        } else {
            ToolbarItem(placement: .topBarLeading) {
                ProfileAvatarButton(profile: profile) { router.select(.profile) }
            }
            if let card {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    showQRButton(card)
                    shareButton(card)
                }
            }
        }
    }

    private func showQRButton(_ card: Card) -> some View {
        Button("Show QR", systemImage: "qrcode") { router.present(.qr(cardID: card.id)) }
    }

    private func shareButton(_ card: Card) -> some View {
        Button("Share", systemImage: "square.and.arrow.up") { router.present(.share(cardID: card.id)) }
    }

    /// The card the carousel shows (same rule as `MyCardsSection`): remembered card, else the default.
    private func activeCard(profile: Profile?) -> Card? {
        let summaries = cards.map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
        let defaultID = CardManagement.effectiveDefaultID(cards: summaries, defaultID: profile?.defaultCardID)
        let id = services.preferences.activeCardID ?? defaultID
        return cards.first { $0.id == id } ?? cards.first { $0.id == defaultID } ?? cards.first
    }

}

/// The avatar in a Liquid Glass circle (the bar's shared glass is a capsule, too wide for one avatar).
private struct ProfileAvatarButton: View {
    let profile: Profile?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            // 44 pt, the diameter of the bar's own glass buttons; the photo/initials fill most of it.
            InitialsAvatar(name: profile?.fullName ?? "", imageData: profile?.photoData, size: 36)
                .frame(width: 44, height: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassOrMaterial(in: Circle(), interactive: true)
        .accessibilityLabel(Text("Profile"))
    }
}
