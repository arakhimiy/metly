import MetlyCapture
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// EVENT_ENDED (SPEC §2.5.31) — full-screen summary after an event ends (manually or automatically).
struct EventEndedScreen: View {
    @Query private var matches: [Event]
    @Environment(AppRouter.self) private var router

    init(eventID: UUID) {
        let id = eventID
        _matches = Query(filter: #Predicate<Event> { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let event = matches.first, !event.isDeleted {
                    EventEndedContent(event: event)
                } else {
                    ContentUnavailableView("Event Not Found", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("This event may have been removed."))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: router.dismiss)
                }
            }
        }
    }
}

private struct EventEndedContent: View {
    let event: Event

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @Query(Connection.live) private var people: [Connection]

    @State private var hasAppeared = false
    @State private var scheduledCount: Int?
    @State private var showsFollowUpLimit = false
    @State private var followUpOpenCount = 0

    var body: some View {
        let members = EventMembership.members(of: event, among: people)
        let stats = EventStats(members: members)
        let withoutNotes = EventMembership.withoutNotes(members)
        List {
            Section {
                EventEndedHero(eventName: event.name, summary: EventCopy.summary(stats), celebrate: hasAppeared)
            }
            .listRowBackground(Color.clear)

            Section {
                EventStatsRow(stats: stats)
            }

            EventEndedActionsSection(pendingCount: stats.withoutFollowUp, scheduledCount: scheduledCount,
                                     hasPeople: !members.isEmpty, isPro: services.entitlements.isPro,
                                     onFollowUp: { followUpWithEveryone(members) }, onExport: export)

            NoNoteYetSection(people: withoutNotes, onAddNote: addNote)
        }
        .bottomActionBar {
            if !withoutNotes.isEmpty {
                Button(action: addNotes) {
                    Text("Add Notes While You Remember")
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                .controlSize(.large)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
        .followUpLimitAlert(isPresented: $showsFollowUpLimit, openCount: followUpOpenCount)
        .sensoryFeedback(.success, trigger: hasAppeared)
        .sensoryFeedback(.success, trigger: scheduledCount)
        .onAppear { hasAppeared = true }
    }

    // MARK: Actions

    /// "Add Notes While You Remember" → EVENT_DETAIL in the People tab.
    private func addNotes() {
        router.open(.eventDetail(id: event.id), in: .people)
    }

    private func addNote(_ person: Connection) {
        router.present(.addContext(connectionID: person.id))
    }

    private func export() {
        router.present(.eventExport(eventID: event.id))
    }

    /// Toasts are hidden under a full-screen cover, so the result is shown in the row instead.
    private func followUpWithEveryone(_ members: [Connection]) {
        let outcome = EventFollowUpPlanner.followUpWithEveryone(eventName: event.name, members: members,
                                                                in: modelContext, limits: services.entitlements.limits)
        if outcome.scheduled > 0 {
            scheduledCount = (scheduledCount ?? 0) + outcome.scheduled
        }
        if outcome.hitLimit {
            followUpOpenCount = outcome.openCountAfter
            showsFollowUpLimit = true
        }
    }
}
