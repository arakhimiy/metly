import MetlyCore
import SwiftData
import SwiftUI

/// Runs `EventLifecycle.endExpiredEvents(in:)` when the view appears and whenever the app becomes
/// active, then shows EVENT_ENDED for the most recently ended event (only when nothing else is presented).
private struct EndsExpiredEventsModifier: ViewModifier {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { endExpiredEvents() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { endExpiredEvents() }
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
