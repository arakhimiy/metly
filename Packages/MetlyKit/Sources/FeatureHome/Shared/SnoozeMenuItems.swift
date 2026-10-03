import SwiftUI

/// MENU_SNOOZE items: Tomorrow · In 3 Days · Next Week · Custom…, each with the resulting day.
struct SnoozeMenuItems: View {
    let dueAt: Date
    let action: (SnoozeOption) -> Void

    var body: some View {
        let now = Date.now
        let calendar = Calendar.current
        let relative = SnoozeOption.isRelativeToToday(dueAt: dueAt, now: now, calendar: calendar)
        ForEach(SnoozeOption.allCases) { option in
            Button {
                action(option)
            } label: {
                Text(option.title(relativeToToday: relative))
                if let date = option.snoozedDate(from: dueAt, now: now, calendar: calendar) {
                    Text(FollowUpDates.shortDay(date, calendar: calendar))
                }
                Image(systemName: option.systemImage)
            }
        }
    }
}
