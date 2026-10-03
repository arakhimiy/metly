import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// HOME tab root (SPEC §2.5.7): offline banner · event row · My Cards · Follow Up Today · Recent.
struct HomeScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services

    @Query(filter: #Predicate<Profile> { $0.deletedAt == nil }) private var profiles: [Profile]
    @Query(Card.live) private var cards: [Card]
    @Query(FollowUp.open) private var openFollowUps: [FollowUp]
    @Query(Connection.live) private var connections: [Connection]
    @Query(Event.active) private var activeEvents: [Event]

    var body: some View {
        let profile = profiles.first
        let now = Date.now
        let calendar = Calendar.current
        let reminders = openFollowUps.filter { $0.connection?.isDeleted != true }
        let due = HomeSelection.dueToday(reminders, now: now, calendar: calendar)
        let todayState = FollowUpTodayState.make(dueCount: due.count,
                                                 upcoming: HomeSelection.upcomingCount(reminders, now: now, calendar: calendar))

        List {
            if !services.network.isOnline {
                OfflineBannerSection()
            }
            HomeEventSection(event: activeEvents.first)
            MyCardsSection(profile: profile, cards: cards)
            FollowUpTodaySection(followUps: Array(due.prefix(HomeSelection.followUpLimit)), state: todayState, now: now)
            if connections.isEmpty {
                GetStartedSection(cardToShare: cardToShare(profile: profile))
            } else {
                RecentSection(people: HomeSelection.recent(connections), now: now)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(greeting(for: profile))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ProfileAvatarButton(profile: profile, action: openProfile)
            }
        }
        .refreshable { await services.sync.syncNow() }
    }

    private func greeting(for profile: Profile?) -> String {
        let first = PersonText.firstName(profile?.fullName ?? "")
        return first.isEmpty ? String(localized: "Hi there") : String(localized: "Hi, \(first)")
    }

    /// Active event's card, else the default card, else the first card.
    private func cardToShare(profile: Profile?) -> Card? {
        if let id = activeEvents.first?.cardID, let card = cards.first(where: { $0.id == id }) { return card }
        if let id = profile?.defaultCardID, let card = cards.first(where: { $0.id == id }) { return card }
        return cards.first
    }

    private func openProfile() {
        router.select(.profile)
    }
}
