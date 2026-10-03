import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct ProfileView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Profile", specID: "PROFILE")
    }
}
public struct NotificationSettingsView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Notifications", specID: "SETTINGS_NOTIFICATIONS")
    }
}
public struct PrivacySettingsView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Privacy & Data", specID: "SETTINGS_PRIVACY")
    }
}
public struct SubscriptionSettingsView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Subscription", specID: "SETTINGS_SUBSCRIPTION")
    }
}
public struct HelpSupportView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Help & Support", specID: "SETTINGS_HELP")
    }
}
public struct DeleteAccountView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Delete Account", specID: "SETTINGS_DELETE_ACCOUNT")
    }
}
public struct PaywallView: View {
    public let trigger: PaywallTrigger

    public init(trigger: PaywallTrigger) {
        self.trigger = trigger
    }

    public var body: some View {
        FeaturePlaceholder("Metly Pro", specID: "PAYWALL")
    }
}
