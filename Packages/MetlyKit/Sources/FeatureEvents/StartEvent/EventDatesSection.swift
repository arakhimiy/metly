import SwiftUI

/// Start / end day pickers (end ≥ start; new events start today or later — PLAN Q16).
struct EventDatesSection: View {
    @Binding var draft: EventDraft
    let mode: EventDraft.Mode

    var body: some View {
        Section {
            DatePicker("Starts", selection: $draft.startDate,
                       in: EventDraft.earliestStart(mode: mode)..., displayedComponents: .date)
            DatePicker("Ends", selection: $draft.endDate,
                       in: draft.earliestEnd(mode: mode)..., displayedComponents: .date)
        } header: {
            Text("Dates")
        } footer: {
            Text(footer)
        }
        .onChange(of: draft.startDate) {
            draft.keepEndAfterStart()
        }
    }

    private var footer: String {
        let issues = draft.issues(mode: mode)
        if issues.contains(.endBeforeStart) { return String(localized: "The event can’t end before it starts.") }
        if issues.contains(.startInPast) { return String(localized: "A new event can’t start in the past.") }
        if issues.contains(.endInPast) { return String(localized: "The event ends by itself after the last day, so pick today or later.") }
        let range = EventCopy.dateRange(start: draft.startDate, end: draft.endDate)
        let days = draft.dayCount()
        return days == 1 ? String(localized: "\(range) · 1 day") : String(localized: "\(range) · \(days) days")
    }
}
