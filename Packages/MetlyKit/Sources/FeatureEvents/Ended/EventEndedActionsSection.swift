import MetlyDesign
import SwiftUI

/// EVENT_ENDED actions: follow up with everyone (replaced by a confirmation once done) and Export to CSV.
struct EventEndedActionsSection: View {
    /// People still without an open reminder.
    let pendingCount: Int
    /// Reminders created from this screen (nil until the action ran).
    let scheduledCount: Int?
    let hasPeople: Bool
    let isPro: Bool
    let onFollowUp: () -> Void
    let onExport: () -> Void

    var body: some View {
        if hasPeople {
            Section {
                if pendingCount > 0 {
                    Button(action: onFollowUp) {
                        Label(EventCopy.followUpEveryone(pendingCount), systemImage: "bell.badge")
                    }
                }
                if let scheduledCount {
                    Label(EventCopy.remindersSet(scheduledCount), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Button(action: onExport) {
                    HStack {
                        Label("Export to CSV", systemImage: "tablecells")
                        Spacer(minLength: 8)
                        if !isPro {
                            ProBadge()
                        }
                    }
                    .contentShape(.rect)
                }
            } footer: {
                if pendingCount > 0 {
                    Text("Sets a reminder for tomorrow at 10:00 for each person without one.")
                }
            }
        }
    }
}
