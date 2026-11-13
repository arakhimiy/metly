import MetlyCapture
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

/// Row actions shared by Home "Follow Up Today" and FOLLOWUPS: each mutates, syncs and shows the
/// SPEC §7.2 toast (with Undo where the SPEC has one).
struct FollowUpActionHandler {
    let context: ModelContext
    let router: AppRouter
    let services: AppServices
    var calendar: Calendar = .current

    func edit(_ followUp: FollowUp) {
        router.present(.reminderEdit(followUpID: followUp.id, connectionID: followUp.connection?.id))
    }

    func openPerson(_ followUp: FollowUp) {
        guard let id = followUp.connection?.id else { return }
        router.push(.connectionDetail(id: id))
    }

    func markDone(_ followUp: FollowUp) {
        let undo = FollowUpMutations.markDone(followUp, in: context)
        services.sync.requestSync()
        router.showToast(String(localized: "Marked Done", bundle: .appStrings), systemImage: "checkmark.circle", undo: syncing(undo))
    }

    /// "Moved Back". Returns false when the Free plan's open-reminder limit blocks it.
    func reopen(_ followUp: FollowUp) -> Bool {
        guard FollowUpPolicy.canSchedule(hasOpenReminder: false, in: context, limits: services.entitlements.limits) else {
            return false
        }
        let undo = FollowUpMutations.reopen(followUp, in: context)
        services.sync.requestSync()
        router.showToast(String(localized: "Moved Back", bundle: .appStrings), systemImage: "arrow.uturn.backward.circle", undo: syncing(undo))
        return true
    }

    /// Tomorrow / In 3 Days / Next Week (base = max(due, today)); Custom… opens REMINDER_EDIT.
    func snooze(_ followUp: FollowUp, _ option: SnoozeOption, now: Date = .now) {
        guard let newDate = option.snoozedDate(from: followUp.dueAt, now: now, calendar: calendar) else {
            edit(followUp)
            return
        }
        let undo = FollowUpMutations.reschedule(followUp, to: newDate, in: context)
        services.sync.requestSync()
        let label = FollowUpDates.dueLabel(newDate, now: now, calendar: calendar)
        router.showToast(String(localized: "Snoozed to \(label)", bundle: .appStrings), systemImage: "clock.arrow.circlepath", undo: syncing(undo))
    }

    /// Immediate delete (long-press menu) with Undo.
    func delete(_ followUp: FollowUp) {
        let undo = FollowUpMutations.delete(followUp, in: context)
        services.sync.requestSync()
        router.showToast(String(localized: "Reminder Deleted", bundle: .appStrings), systemImage: "trash", undo: syncing(undo))
    }

    /// Opens Telegram (app, then t.me; by phone number when no username) / Mail / Phone for the reminder's channel.
    func openChannel(_ followUp: FollowUp, with openURL: OpenURLAction) {
        let channel = followUp.channel
        guard let target = ChannelLink.target(channel, for: followUp.connection) else { return }
        router.showToast(String(localized: "Opening \(ChannelLink.actionTitle(channel))", bundle: .appStrings), systemImage: channel.symbolName)
        openURL(target.primary) { accepted in
            if !accepted, let fallback = target.fallback { openURL(fallback) }
        }
    }

    private func syncing(_ undo: @escaping FollowUpMutations.Undo) -> FollowUpMutations.Undo {
        let sync = services.sync
        return {
            undo()
            sync.requestSync()
        }
    }
}
