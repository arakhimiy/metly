import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Runs `EventLifecycle.endExpiredEvents(in:)` when the view appears, whenever the app becomes active
/// and — while it stays in the foreground — at the moment the next active event's last day is over,
/// then shows EVENT_ENDED for the most recently ended event (only when nothing else is presented).
private struct EndsExpiredEventsModifier: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(Event.active) private var activeEvents: [Event]

    func body(content: Content) -> some View {
        let nextAutoEnd = EventLifecycle.nextAutoEnd(of: activeEvents)
        content
            .task { endExpiredEvents() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { endExpiredEvents() }
            }
            .task(id: nextAutoEnd) {
                // Restarts whenever an event starts, ends, resumes or changes dates.
                guard let nextAutoEnd else { return }
                try? await Task.sleep(for: .seconds(max(nextAutoEnd.timeIntervalSinceNow, 0) + 1))
                guard !Task.isCancelled else { return }
                endExpiredEvents()
            }
    }

    private func endExpiredEvents() {
        let ended = EventLifecycle.endExpiredEvents(in: modelContext)
        guard let last = ended.last, router.phase == .main, router.presentations.isEmpty else { return }
        router.present(.eventEnded(eventID: last))
    }
}

public extension View {
    /// Auto-end for Event mode (SPEC §3.17 step 5). Attach once to the signed-in root (e.g. `MainTabView`).
    func endsExpiredEvents() -> some View {
        modifier(EndsExpiredEventsModifier())
    }
}
