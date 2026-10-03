import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// FOLLOWUPS (SPEC §2.5.14): Overdue · Today · This Week · Later · Done (collapsible), swipe right
/// Done / swipe left Snooze (+1 day), MENU_REMINDER_ROW, "+" → REMINDER_EDIT (Free limit first).
struct FollowUpsScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    @Query(filter: #Predicate<FollowUp> { $0.deletedAt == nil }, sort: \FollowUp.dueAt) private var followUps: [FollowUp]
    @Query(filter: #Predicate<Profile> { $0.deletedAt == nil }) private var profiles: [Profile]

    @SceneStorage("followUps.showsDone") private var showsDone = false
    @State private var showsLimitAlert = false
    @State private var openCount = 0
    @State private var systemNotificationsDenied = false
    @State private var completedCount = 0
    @State private var snoozedCount = 0

    var body: some View {
        let now = Date.now
        let visible = followUps.filter { $0.connection?.isDeleted != true }
        let groups = FollowUpGrouping.groups(visible, now: now, calendar: .current)
        let lastOpenBucket = groups.last { $0.bucket != .done }?.bucket

        Group {
            if visible.isEmpty {
                FollowUpsEmptyView(onAdd: addReminder)
            } else {
                List {
                    if let notice = remindersOffNotice(hasOpen: lastOpenBucket != nil) {
                        RemindersOffSection(notice: notice)
                    }
                    ForEach(groups) { group in
                        FollowUpGroupSection(group: group, now: now, showsDone: $showsDone,
                                             showsSwipeHint: group.bucket == lastOpenBucket,
                                             actions: actions(for:))
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("Follow-ups")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("New Reminder", systemImage: "plus", action: addReminder)
            }
        }
        .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: openCount)
        .sensoryFeedback(.success, trigger: completedCount)
        .sensoryFeedback(.selection, trigger: snoozedCount)
        .task(id: scenePhase) {
            systemNotificationsDenied = await FollowUpNotificationScheduler.isDenied()
        }
    }

    private var handler: FollowUpActionHandler {
        FollowUpActionHandler(context: modelContext, router: router, services: services)
    }

    private func remindersOffNotice(hasOpen: Bool) -> RemindersOffSection.Notice? {
        guard hasOpen else { return nil }
        if systemNotificationsDenied { return .systemDenied }
        if let prefs = profiles.first?.notificationPrefs, !prefs.followUpReminders { return .turnedOff }
        return nil
    }

    private func actions(for followUp: FollowUp) -> FollowUpRow.Actions {
        FollowUpRow.Actions(
            edit: { handler.edit(followUp) },
            openPerson: { handler.openPerson(followUp) },
            snooze: { option in
                handler.snooze(followUp, option)
                if option != .custom { snoozedCount += 1 }
            },
            toggleDone: { toggleDone(followUp) },
            delete: { handler.delete(followUp) }
        )
    }

    private func toggleDone(_ followUp: FollowUp) {
        if followUp.isDone {
            guard handler.reopen(followUp) else {
                openCount = FollowUpPolicy.openCount(in: modelContext)
                showsLimitAlert = true
                return
            }
        } else {
            handler.markDone(followUp)
            completedCount += 1
        }
    }

    /// "+": Free plan limit check first (SPEC §2.5.14), then REMINDER_EDIT.
    private func addReminder() {
        guard FollowUpPolicy.canSchedule(hasOpenReminder: false, in: modelContext, limits: services.entitlements.limits) else {
            openCount = FollowUpPolicy.openCount(in: modelContext)
            showsLimitAlert = true
            return
        }
        router.present(.reminderEdit(followUpID: nil, connectionID: nil))
    }
}

/// "No Follow-ups Yet" (SPEC §7.4).
private struct FollowUpsEmptyView: View {
    let onAdd: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Follow-ups Yet", systemImage: "bell")
        } description: {
            Text("Add one right after you connect — it takes 2 seconds.")
        } actions: {
            Button("New Reminder", action: onAdd)
                .buttonStyle(.borderedProminent)
        }
    }
}
