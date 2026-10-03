import MetlyCore
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers;
// replace the bodies with the real screens.

public struct OnboardingFlowView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Welcome", specID: "ONB_WELCOME · AUTH_SIGNUP")
    }
}
public struct SetupFlowView: View {
    public init() {}

    public var body: some View {
        FeaturePlaceholder("Setup", specID: "SETUP_PROFILE · SETUP_PERMISSIONS")
    }
}
public struct DeferredWelcomeView: View {
    public let invite: DeferredInvite

    public init(invite: DeferredInvite) {
        self.invite = invite
    }

    public var body: some View {
        FeaturePlaceholder("Welcome to Metly", specID: "DEFERRED_WELCOME")
    }
}
