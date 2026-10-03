import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct HomeView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Home", specID: "HOME")
    }
}
public struct FollowUpsView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Follow-ups", specID: "FOLLOWUPS")
    }
}
public struct ReminderEditSheet: View {
    public let followUpID: UUID?
    public let connectionID: UUID?

    public init(followUpID: UUID?,connectionID: UUID?) {
        self.followUpID = followUpID
        self.connectionID = connectionID
    }

    public var body: some View {
        FeaturePlaceholder("Reminder", specID: "REMINDER_EDIT")
    }
}
