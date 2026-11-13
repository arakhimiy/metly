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
        let base = String(localized: "Sets a reminder for tomorrow at 10:00 for each person without one.", bundle: .appStrings)
        guard let remaining, remaining < count else { return base }
        switch remaining {
        case 0: return String(localized: "You’re using every active reminder the Free plan includes.", bundle: .appStrings)
        case 1: return String(localized: "\(base) The Free plan has room for 1 more.", bundle: .appStrings)
        default: return String(localized: "\(base) The Free plan has room for \(remaining) more.", bundle: .appStrings)
        }
    }
}
