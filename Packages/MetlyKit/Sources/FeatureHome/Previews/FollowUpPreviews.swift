#if DEBUG
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

// SPEC Appendix A states 8–12: FOLLOWUPS (full / empty), REMINDER_EDIT (new / edit), ALERT_FU_LIMIT.
// Swipe actions and MENU_REMINDER_ROW need interaction: use Live Preview on "Follow-ups · full".

#Preview("Follow-ups · full") {
    NavigationStack {
        HomePreviewPrepared(prepare: HomePreviewData.addLaterAndDone) {
            FollowUpsView()
        }
    }
    .metlyPreview(.full)
}

#Preview("Follow-ups · empty") {
    NavigationStack { FollowUpsView() }
        .metlyPreview(.empty)
}

#Preview("Follow-ups · dark, large text") {
    NavigationStack {
        HomePreviewPrepared(prepare: HomePreviewData.addLaterAndDone) {
            FollowUpsView()
        }
    }
    .metlyPreview(.full)
    .preferredColorScheme(.dark)
    .environment(\.dynamicTypeSize, .accessibility1)
}

#Preview("Reminder · new") {
    ReminderEditSheet(followUpID: nil, connectionID: nil)
        .metlyPreview(.full)
}

#Preview("Reminder · new for a person") {
    ReminderEditSheet(followUpID: nil, connectionID: PreviewSeed.firstConnectionID)
        .metlyPreview(.full)
}

#Preview("Reminder · edit") {
    HomePreviewReminder { reminder in
        ReminderEditSheet(followUpID: reminder.id, connectionID: reminder.connection?.id)
    }
    .metlyPreview(.full)
}

#Preview("Reminder · Free limit reached") {
    HomePreviewReminder(prepare: HomePreviewData.fillToFreeLimit) { reminder in
        ReminderEditScreen(existing: nil, person: reminder.connection, isPersonFixed: true,
                           showsLimitAlert: true, openCount: 5)
    }
    .metlyPreview(.full)
}
#endif
