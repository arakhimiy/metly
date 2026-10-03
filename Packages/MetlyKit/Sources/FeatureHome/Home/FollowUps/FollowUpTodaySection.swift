import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// "Follow Up Today" (SPEC §2.5.7): up to three overdue/today reminders with channel action,
/// Snooze menu and Done (+Undo); empty copy from SPEC §7.4; See All → FOLLOWUPS.
struct FollowUpTodaySection: View {
    let followUps: [FollowUp]
    let state: FollowUpTodayState
    let now: Date

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @State private var completedCount = 0
    @State private var snoozedCount = 0

    var body: some View {
        Section {
            switch state {
            case .due:
                ForEach(followUps) { followUp in
                    FollowUpTodayRow(
                        followUp: followUp,
                        now: now,
                        actions: FollowUpTodayRow.Actions(
                            edit: { handler.edit(followUp) },
                            openChannel: { handler.openChannel(followUp, with: openURL) },
                            snooze: { snooze(followUp, $0) },
                            done: { markDone(followUp) }
                        )
                    )
                }
            case .nothingDue(let upcoming):
                Text("Nothing due today. \(upcoming) coming up.")
                    .foregroundStyle(.secondary)
            case .noFollowUps:
                Text("No follow-ups yet. Add one right after you connect — it takes 2 seconds.")
                    .foregroundStyle(.secondary)
            }
        } header: {
            HomeSectionHeader(Text("Follow Up Today")) {
                Button("See All", action: seeAll)
            }
        } footer: {
            if case .due(_, let overflow) = state, overflow > 0 {
                Text("\(overflow) more due today.")
            }
        }
        .headerProminence(.increased)
        .sensoryFeedback(.success, trigger: completedCount)
        .sensoryFeedback(.selection, trigger: snoozedCount)
    }

    private var handler: FollowUpActionHandler {
        FollowUpActionHandler(context: modelContext, router: router, services: services)
    }

    private func seeAll() {
        router.push(.followUps)
    }

    private func markDone(_ followUp: FollowUp) {
        handler.markDone(followUp)
        completedCount += 1
    }

    private func snooze(_ followUp: FollowUp, _ option: SnoozeOption) {
        handler.snooze(followUp, option)
        if option != .custom { snoozedCount += 1 }
    }
}
