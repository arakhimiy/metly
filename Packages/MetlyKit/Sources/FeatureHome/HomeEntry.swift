import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

/// HOME tab root (SPEC §2.5.7).
public struct HomeView: View {
    public init() {}

    public var body: some View {
        HomeScreen()
    }
}

/// FOLLOWUPS (push, SPEC §2.5.14).
public struct FollowUpsView: View {
    public init() {}

    public var body: some View {
        FollowUpsScreen()
    }
}

/// REMINDER_EDIT (large sheet, SPEC §2.5.34). `connectionID` fixes the person for a new reminder.
public struct ReminderEditSheet: View {
    public let followUpID: UUID?
    public let connectionID: UUID?

    public init(followUpID: UUID?,connectionID: UUID?) {
        self.followUpID = followUpID
        self.connectionID = connectionID
    }

    public var body: some View {
        ReminderEditLoader(followUpID: followUpID, connectionID: connectionID)
    }
}
