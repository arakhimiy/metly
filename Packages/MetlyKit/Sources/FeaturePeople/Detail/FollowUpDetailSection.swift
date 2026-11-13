import MetlyCapture
import MetlyCore
import MetlyData
import SwiftUI

/// The open reminder (Done / tap to edit) or Add Reminder. No day chips (owner, 2026-11-13): the
/// reminder editor sets the date.
struct FollowUpDetailSection: View {
    let person: Connection

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @State private var showsLimitAlert = false
    @State private var openCount = 0
    @State private var doneCount = 0

    var body: some View {
        let reminder = person.openFollowUp
        Section {
            if let reminder {
                OpenReminderRow(reminder: reminder, onOpen: { edit(reminder) }, onDone: { markDone(reminder) })
            }
            if reminder == nil {
                Button("Add Reminder…", systemImage: "bell.badge", action: addReminder)
            }
        } header: {
            Text("Follow Up")
        } footer: {
            Text(reminder == nil ? "Pick a day. \(Brand.appName) reminds you with your note." : "Tap the reminder to change it.")
        }
        .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: openCount)
        .sensoryFeedback(.success, trigger: doneCount)
    }

    private func addReminder() {
        let limits = services.entitlements.limits
        guard FollowUpPolicy.canSchedule(hasOpenReminder: false, in: modelContext, limits: limits) else {
            openCount = FollowUpPolicy.openCount(in: modelContext)
            showsLimitAlert = true
            return
        }
        router.present(.reminderEdit(followUpID: nil, connectionID: person.id))
    }

    private func edit(_ reminder: FollowUp) {
        router.present(.reminderEdit(followUpID: reminder.id, connectionID: person.id))
    }

    private func markDone(_ reminder: FollowUp) {
        let undo = PeopleActions.markDone(reminder, in: modelContext)
        doneCount += 1
        router.showToast(String(localized: "Marked Done", bundle: .appStrings), systemImage: "checkmark.circle", undo: undo)
    }
}

private struct OpenReminderRow: View {
    let reminder: FollowUp
    let onOpen: () -> Void
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reminder.title)
                            .foregroundStyle(.primary)
                        Text("\(reminder.dueAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())) · \(reminder.channel.title)")
                            .font(.subheadline)
                            .foregroundStyle(reminder.dueAt < .now ? .red : .secondary)
                    }
                } icon: {
                    Image(systemName: "bell.fill")
                        .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Edits the reminder")

            Button("Done", action: onDone)
                .buttonStyle(.bordered)
                .buttonBorderShape(.capsule)
                .accessibilityLabel("Mark \(reminder.title) done")
        }
    }
}
