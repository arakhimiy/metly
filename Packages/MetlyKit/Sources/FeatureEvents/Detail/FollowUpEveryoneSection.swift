import SwiftUI

/// "Follow Up with Everyone I Haven't Yet ({N})" — a reminder for tomorrow for each person without one.
struct FollowUpEveryoneSection: View {
    /// People without an open reminder.
    let count: Int
    /// Reminders the Free plan still allows (nil on Pro).
    let remaining: Int?
    let onFollowUp: () -> Void

    var body: some View {
        Section {
            Button(action: onFollowUp) {
                Label(EventCopy.followUpEveryone(count), systemImage: "bell.badge")
            }
        } footer: {
            Text(footer)
        }
    }

    private var footer: String {
        let base = "Sets a reminder for tomorrow at 10:00 for each person without one."
        guard let remaining, remaining < count else { return base }
        switch remaining {
        case 0: return "You’re using every active reminder the Free plan includes."
        case 1: return "\(base) The Free plan has room for 1 more."
        default: return "\(base) The Free plan has room for \(remaining) more."
        }
    }
}
