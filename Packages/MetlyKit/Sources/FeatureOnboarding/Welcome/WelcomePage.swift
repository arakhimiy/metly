import MetlyCore
import SwiftUI

/// The three ONB_WELCOME pages (mirror the product pillars, SPEC §1.1).
enum WelcomePage: Int, CaseIterable, Identifiable, Hashable {
    case share, context, followUp

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .share: "Never Forget Someone You Meet"
        case .context: "Context Saves Itself"
        case .followUp: "Follow Up on Time"
        }
    }

    var subtitle: LocalizedStringKey {
        switch self {
        case .share: "Share your card, remember where you met, and follow up on time."
        case .context: "Event, place and time are added the moment you connect. Add a note by voice."
        case .followUp: "Pick a day in one tap. \(Brand.appName) reminds you why, so you know what to say."
        }
    }

    var next: WelcomePage? {
        WelcomePage(rawValue: rawValue + 1)
    }

    var isLast: Bool { next == nil }
}
