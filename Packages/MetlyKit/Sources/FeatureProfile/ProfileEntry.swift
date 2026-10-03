import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// the bodies delegate to the internal screens of this module.

/// PROFILE tab root.
public struct ProfileView: View {
    public init() {}

    public var body: some View {
        ProfileScreen()
    }
}

/// SETTINGS_NOTIFICATIONS.
public struct NotificationSettingsView: View {
    public init() {}

    public var body: some View {
        NotificationSettingsScreen()
    }
}

/// SETTINGS_PRIVACY.
public struct PrivacySettingsView: View {
    public init() {}

    public var body: some View {
        PrivacySettingsScreen()
    }
}

/// SETTINGS_SUBSCRIPTION.
public struct SubscriptionSettingsView: View {
    public init() {}

    public var body: some View {
        SubscriptionSettingsScreen()
    }
}

/// SETTINGS_HELP.
public struct HelpSupportView: View {
    public init() {}

    public var body: some View {
        HelpSupportScreen()
    }
}

/// SETTINGS_DELETE_ACCOUNT.
public struct DeleteAccountView: View {
    public init() {}

    public var body: some View {
        DeleteAccountScreen()
    }
}

/// PAYWALL (cover).
public struct PaywallView: View {
    public let trigger: PaywallTrigger

    public init(trigger: PaywallTrigger) {
        self.trigger = trigger
    }

    public var body: some View {
        PaywallScreen(trigger: trigger)
    }
}
