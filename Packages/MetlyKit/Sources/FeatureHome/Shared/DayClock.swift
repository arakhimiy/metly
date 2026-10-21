import Foundation
import SwiftUI

/// "Now" for screens whose rows depend on the calendar day (Overdue / Today / Tomorrow, "Follow Up Today").
///
/// Reading `now` in `body` makes the view depend on the clock, and `.tracksDayChanges(_:)` bumps it at
/// local midnight and whenever the app returns to the foreground — otherwise a screen left open (or in
/// the background) overnight keeps yesterday's buckets until some data happens to change. Between
/// bumps `now` is still the current time on every render.
struct DayClock: Equatable {
    fileprivate var generation = 0

    var now: Date { .now }
}

extension View {
    func tracksDayChanges(_ clock: Binding<DayClock>) -> some View {
        modifier(DayChangeModifier(clock: clock))
    }
}

private struct DayChangeModifier: ViewModifier {
    @Binding var clock: DayClock
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task(id: clock.generation) {
                let midnight = FollowUpDates.startOfNextDay(after: .now, calendar: .current)
                try? await Task.sleep(for: .seconds(max(midnight.timeIntervalSinceNow, 0) + 1))
                guard !Task.isCancelled else { return }
                clock.generation += 1
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { clock.generation += 1 }
            }
    }
}
