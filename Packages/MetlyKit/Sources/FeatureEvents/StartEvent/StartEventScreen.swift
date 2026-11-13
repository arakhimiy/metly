import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// START_EVENT (SPEC §2.5.30) — new or edit. Medium + large sheet with its own navigation bar.
struct StartEventScreen: View {
    let eventID: UUID?

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(Card.live) private var cards: [Card]
    @Query(filter: #Predicate<Profile> { $0.deletedAt == nil }) private var profiles: [Profile]

    @State private var draft = EventDraft()
    @State private var mode: EventDraft.Mode = .new
    @State private var loadState = LoadState.loading
    @State private var calendarProvider: CalendarSuggestionProvider
    @State private var showsLimitAlert: Bool
    @State private var activeEventName = ""
    @State private var pickCount = 0
    @State private var savedCount = 0
    @FocusState private var focus: EventField?

    private enum LoadState { case loading, ready, missing }

    /// - Parameters:
    ///   - calendarProvider: injected by previews; the real one is created lazily and cheaply.
    ///   - showsLimitAlert: previews only — starts with ALERT_ONE_EVENT on screen.
    init(eventID: UUID?, calendarProvider: CalendarSuggestionProvider? = nil, showsLimitAlert: Bool = false) {
        self.eventID = eventID
        _calendarProvider = State(initialValue: calendarProvider ?? CalendarSuggestionProvider())
        _showsLimitAlert = State(initialValue: showsLimitAlert)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch loadState {
                case .loading:
                    ProgressView()
                case .missing:
                    ContentUnavailableView("Event Not Found", systemImage: "calendar.badge.exclamationmark",
                                           description: Text("This event may have been removed."))
                case .ready:
                    Form {
                        if mode.isNew {
                            CalendarSuggestionsSection(provider: calendarProvider,
                                                       selectedIdentifier: draft.calendarEventIdentifier,
                                                       onPick: apply)
                        }
                        EventInfoSection(draft: $draft, focus: $focus)
                        EventDatesSection(draft: $draft, mode: mode)
                        CardToShareSection(cards: cards, profile: profiles.first, selection: $draft.cardID)
                    }
                }
            }
            .navigationTitle(mode.isNew ? "Start Event" : "Edit Event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: router.dismiss)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(mode.isNew ? "Start" : "Save", action: save)
                        .disabled(loadState != .ready || !draft.isValid(mode: mode))
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .oneActiveEventAlert(isPresented: $showsLimitAlert, activeEventName: activeEventName)
        .sensoryFeedback(.selection, trigger: pickCount)
        .sensoryFeedback(.success, trigger: savedCount)
        .task { load() }
        .onChange(of: scenePhase) { _, phase in
            // Back from Settings after allowing calendar access.
            if phase == .active, mode.isNew { calendarProvider.refresh() }
        }
    }

    // MARK: Actions

    private func load() {
        guard loadState == .loading else { return }
        if let eventID {
            guard let event = modelContext.record(Event.self, id: eventID), !event.isDeleted else {
                loadState = .missing
                return
            }
            mode = event.isActive ? .editActive : .editEnded
            draft = EventDraft(event: event)
        } else {
            mode = .new
            draft = EventDraft(cardID: nil)
            calendarProvider.refresh()
        }
        if draft.cardID.map({ id in cards.contains { $0.id == id } }) != true {
            draft.cardID = modelContext.defaultCard()?.id ?? cards.first?.id
        }
        if showsLimitAlert {
            activeEventName = EventLifecycle.activeEvents(in: modelContext).first?.name ?? ""
        }
        loadState = .ready
    }

    private func apply(_ suggestion: CalendarSuggestion) {
        draft.apply(suggestion)
        pickCount += 1
    }

    private func save() {
        guard draft.isValid(mode: mode) else { return }
        if mode.isNew {
            start()
        } else if let eventID, let event = modelContext.record(Event.self, id: eventID) {
            EventLifecycle.update(event, with: draft, in: modelContext)
            finish(String(localized: "Event Updated", bundle: .appStrings), systemImage: "checkmark.circle")
        }
    }

    private func start() {
        guard EventLifecycle.canActivate(in: modelContext, limits: services.entitlements.limits) else {
            activeEventName = EventLifecycle.activeEvents(in: modelContext).first?.name ?? ""
            showsLimitAlert = true
            return
        }
        modelContext.insert(draft.makeEvent())
        try? modelContext.save()
        finish(String(localized: "Event Started", bundle: .appStrings), systemImage: "flag")
    }

    private func finish(_ message: String, systemImage: String) {
        savedCount += 1
        router.dismiss()
        router.showToast(message, systemImage: systemImage)
    }
}

/// Focus chain of the event fields.
enum EventField: Hashable {
    case name, place, city
}
