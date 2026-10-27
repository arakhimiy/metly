import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// EVENT_DETAIL (SPEC §2.5.15) — loads the event live by id.
struct EventDetailScreen: View {
    @Query private var matches: [Event]

    init(eventID: UUID) {
        let id = eventID
        _matches = Query(filter: #Predicate<Event> { $0.id == id })
    }

    var body: some View {
        if let event = matches.first, !event.isDeleted {
            EventDetailContent(event: event)
        } else {
            ContentUnavailableView("Event Not Found", systemImage: "calendar.badge.exclamationmark",
                                   description: Text("This event may have been removed."))
                .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct EventDetailContent: View {
    let event: Event

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(Connection.live) private var people: [Connection]
    @Query(EventDetailContent.liveEvents) private var events: [Event]
    @Query(Card.live) private var cards: [Card]
    @Query(FollowUp.open) private var openFollowUps: [FollowUp]
    @Query(filter: #Predicate<Profile> { $0.deletedAt == nil }) private var profiles: [Profile]

    @State private var confirmsEnd = false
    @State private var showsEventLimit = false
    @State private var activeEventName = ""
    @State private var showsFollowUpLimit = false
    @State private var followUpOpenCount = 0
    @State private var successCount = 0

    private static var liveEvents: FetchDescriptor<Event> {
        FetchDescriptor(predicate: #Predicate { $0.deletedAt == nil }, sortBy: [SortDescriptor(\.startDate, order: .reverse)])
    }

    var body: some View {
        let members = EventMembership.members(of: event, among: people)
        let stats = EventStats(members: members)
        let card = sharedCard
        List {
            EventHeaderSection(event: event)
            Section {
                EventStatsRow(stats: stats)
            }
            EventCardSection(event: event, card: card, profile: profiles.first, onShowQR: showQR)
            if stats.withoutFollowUp > 0 {
                FollowUpEveryoneSection(count: stats.withoutFollowUp, remaining: remainingReminders) {
                    followUpWithEveryone(members)
                }
            }
            NoNoteYetSection(people: EventMembership.withoutNotes(members), onAddNote: addNote)
            EventPeopleSection(people: members, isActive: event.isActive, canShowQR: card != nil,
                               onShowQR: showQR, onJustMet: justMet)
            EventManageSection(isActive: event.isActive, canResume: canResume, isPro: services.entitlements.isPro,
                               onExport: export, onResume: resume, onEnd: { confirmsEnd = true })
        }
        .navigationTitle(event.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if canEdit {
                    Button("Edit", action: edit)
                }
            }
        }
        .alert("End \(event.name)?", isPresented: $confirmsEnd) {
            Button("Cancel", role: .cancel) {}
            Button("End Event", role: .destructive, action: endEvent)
        } message: {
            Text("New connections won’t be added to it. You’ll get a summary.")
        }
        .oneActiveEventAlert(isPresented: $showsEventLimit, activeEventName: activeEventName)
        .followUpLimitAlert(isPresented: $showsFollowUpLimit, openCount: followUpOpenCount)
        .sensoryFeedback(.success, trigger: successCount)
    }

    // MARK: Derived

    /// Edit is offered for the current or the most recent event (SPEC §2.5.15).
    private var isMostRecent: Bool { events.first?.id == event.id }
    private var canEdit: Bool { event.isActive || isMostRecent }
    private var canResume: Bool { !event.isActive && isMostRecent }

    private var sharedCard: Card? {
        if let id = event.cardID, let card = cards.first(where: { $0.id == id }) { return card }
        return cards.first { $0.id == profiles.first?.defaultCardID } ?? cards.first
    }

    /// Reminders the Free plan still allows (nil on Pro). Counted like `FollowUpPolicy.openCount(in:)`.
    private var remainingReminders: Int? {
        let openCount = openFollowUps.count { $0.connection?.isDeleted != true }
        return EventFollowUpPlanner.remainingCapacity(openCount: openCount, limits: services.entitlements.limits)
    }

    // MARK: Actions

    private func edit() {
        router.present(.startEvent(eventID: event.id))
    }

    private func showQR() {
        guard let card = sharedCard else { return }
        router.present(.qr(cardID: card.id))
    }

    private func justMet() {
        router.present(.justMet(cardID: sharedCard?.id))
    }

    private func addNote(_ person: Connection) {
        router.present(.addContext(connectionID: person.id))
    }

    private func export() {
        router.present(.eventExport(eventID: event.id))
    }

    private func followUpWithEveryone(_ members: [Connection]) {
        let outcome = EventFollowUpPlanner.followUpWithEveryone(eventName: event.name, members: members,
                                                                in: modelContext, limits: services.entitlements.limits)
        if outcome.scheduled > 0 {
            successCount += 1
            router.showToast(EventCopy.remindersSet(outcome.scheduled), systemImage: "bell.badge")
        }
        if outcome.hitLimit {
            followUpOpenCount = outcome.openCountAfter
            showsFollowUpLimit = true
        }
    }

    private func resume() {
        guard EventLifecycle.canActivate(in: modelContext, limits: services.entitlements.limits, excluding: event.id) else {
            activeEventName = EventLifecycle.activeEvents(in: modelContext, excluding: event.id).first?.name ?? ""
            showsEventLimit = true
            return
        }
        EventLifecycle.resume(event)
        try? modelContext.save()
        successCount += 1
        router.showToast(String(localized: "Event Resumed"), systemImage: "play.circle")
    }

    private func endEvent() {
        EventLifecycle.end(event)
        try? modelContext.save()
        router.present(.eventEnded(eventID: event.id))
    }
}
