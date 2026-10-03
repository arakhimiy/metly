import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers.

/// Root phase `.onboarding`: ONB_WELCOME → AUTH_SIGNUP (→ sign-in mode).
public struct OnboardingFlowView: View {
    @State private var path: [OnboardingRoute] = []

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            WelcomeView { path.append(.signUp) }
                .navigationDestination(for: OnboardingRoute.self) { route in
                    AuthView(mode: route.authMode)
                }
        }
    }
}

/// Root phase `.setup`: SETUP_PROFILE → SETUP_PERMISSIONS → main (CARD_CREATE or the pending invite).
public struct SetupFlowView: View {
    @State private var path: [SetupRoute] = []

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            SetupProfileView { path.append(.permissions) }
                .navigationDestination(for: SetupRoute.self) { _ in
                    SetupPermissionsView()
                }
        }
    }
}

/// Root phase `.deferredWelcome`: DEFERRED_WELCOME → AUTH_SIGNUP.
///
/// "Connect with {first}" stores `invite.cardSlug` as the pending invite (`OnboardingStore`) and
/// pushes sign-in. When onboarding ends — after SETUP_PERMISSIONS, or right after sign-in for an
/// existing account — `OnboardingCoordinator.enterMain` opens
/// `router.open(.scannedCard(ScannedCardPayload(url:slug:)), in: .scan)` instead of CARD_CREATE.
/// "Not Now" clears it and shows the regular welcome pages.
public struct DeferredWelcomeView: View {
    public let invite: DeferredInvite

    @Environment(AppRouter.self) private var router
    @State private var path: [OnboardingRoute] = []

    public init(invite: DeferredInvite) {
        self.invite = invite
    }

    public var body: some View {
        NavigationStack(path: $path) {
            DeferredWelcomeScreen(invite: invite, onConnect: connect, onNotNow: notNow)
                .navigationDestination(for: OnboardingRoute.self) { route in
                    AuthView(mode: route.authMode)
                }
        }
    }

    private func connect() {
        OnboardingStore().pendingInviteSlug = invite.cardSlug
        path.append(.signUp)
    }

    private func notNow() {
        OnboardingStore().pendingInviteSlug = nil
        router.phase = .onboarding
    }
}

#Preview("Onboarding flow") {
    OnboardingFlowView()
        .metlyPreview(.signedOut)
}

#Preview("Setup flow") {
    SetupFlowView()
        .metlyPreview(.signedOut)
}

#Preview("Deferred welcome flow") {
    DeferredWelcomeView(invite: OnboardingSamples.invite)
        .metlyPreview(.signedOut)
}
