import MetlyCore
import SwiftData
import SwiftUI

/// Quick picks (single select; the first pick checks the Free limit) + Date (custom) · Time · To Do · Via.
struct FollowUpSection: View {
    @Binding var draft: CaptureDraft

    @Environment(\.modelContext) private var modelContext
    @Environment(AppServices.self) private var services
    @State private var showsLimitAlert = false
    @State private var openCount = 0

    var body: some View {
        Section {
            FollowUpQuickPicker(selection: draft.followUp?.pick, onSelect: select)
            if let followUp = Binding($draft.followUp) {
                FollowUpDetailRows(followUp: followUp)
            }
        } header: {
            Text("Follow Up")
        } footer: {
            Text(FollowUpSummary.footer(for: draft))
        }
        .followUpLimitAlert(isPresented: $showsLimitAlert, openCount: openCount)
    }

    private func select(_ pick: FollowUpQuickPick) {
        if draft.followUp?.pick == pick {
            draft.followUp = nil
            return
        }
        if var followUp = draft.followUp {
            followUp.pick = pick
            draft.followUp = followUp
            return
        }
        let limits = services.entitlements.limits
        guard FollowUpPolicy.canSchedule(hasOpenReminder: draft.existingReminder != nil, in: modelContext, limits: limits) else {
            openCount = FollowUpPolicy.openCount(in: modelContext)
            showsLimitAlert = true
            return
        }
        var followUp = FollowUpDraft(pick: pick, channel: draft.existingReminder?.channel ?? draft.preferredChannel)
        if let existing = draft.existingReminder {
            followUp.time = existing.dueAt
        }
        draft.followUp = followUp
    }
}

private struct FollowUpDetailRows: View {
    @Binding var followUp: FollowUpDraft

    var body: some View {
        if followUp.pick == .custom {
            DatePicker("Date", selection: $followUp.customDate, in: Calendar.current.startOfDay(for: .now)...,
                       displayedComponents: .date)
        }
        DatePicker("Time", selection: $followUp.time, displayedComponents: .hourAndMinute)
        LabeledContent("To Do") {
            TextField("To Do", text: $followUp.title, prompt: Text("Send deck"))
                .multilineTextAlignment(.trailing)
                .submitLabel(.done)
        }
        Picker("Reply Via", selection: $followUp.channel) {
            ForEach(FollowUpChannel.allCases) { channel in
                Text(channel.title).tag(channel)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Footer copy: "Tanishly will remind you tomorrow at 10:00. Only you see it."
enum FollowUpSummary {
    static func footer(for draft: CaptureDraft, now: Date = .now, calendar: Calendar = .current) -> String {
        if let followUp = draft.followUp {
            let due = followUp.dueDate(now: now, calendar: calendar)
            let app = Brand.appName
            let time = due.formatted(date: .omitted, time: .shortened)
            // Whole sentences per day, so translations never glue fragments together.
            if calendar.isDate(due, inSameDayAs: now) {
                return String(localized: "\(app) will remind you today at \(time). Only you see it.")
            }
            if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
                return String(localized: "\(app) will remind you tomorrow at \(time). Only you see it.")
            }
            let day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
            return String(localized: "\(app) will remind you on \(day) at \(time). Only you see it.")
        }
        if let existing = draft.existingReminder {
            return String(localized: "Reminder set for \(existing.dueAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())) at \(existing.dueAt.formatted(date: .omitted, time: .shortened)). Pick a day to reschedule.")
        }
        return String(localized: "Pick a day. \(Brand.appName) reminds you with your note.")
    }

    /// "today", "tomorrow" or "on Tue, Sep 29".
    static func dayPhrase(for due: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        if calendar.isDate(due, inSameDayAs: now) { return String(localized: "today", comment: "Fragment: “… will remind you today”") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(due, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow", comment: "Fragment: “… will remind you tomorrow”")
        }
        let day = due.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        return String(localized: "on \(day)", comment: "Fragment: “… will remind you on Tue, Sep 29”")
    }
}
