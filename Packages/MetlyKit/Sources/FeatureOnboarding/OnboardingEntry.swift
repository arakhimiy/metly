import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

// FROZEN ENTRY POINTS — the app RouteResolver constructs these. Keep the initialisers.

/// Root phase `.onboarding`: ONB_LANGUAGE (until a language is picked) → ONB_WELCOME → AUTH_SIGNUP
/// (→ sign-in mode).
public struct OnboardingFlowView: View {
    @Environment(AppServices.self) private var services
    @State private var path: [OnboardingRoute] = []

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            if services.preferences.language == nil {
                // Picking re-renders the app in that language (MetlyApp keys the root on it), and
                // this flow comes back with the welcome pages.
                LanguagePickerView { services.preferences.language = $0 }
            } else {
                WelcomeView { path.append(.signUp) }
                    .navigationDestination(for: OnboardingRoute.self) { route in
                        AuthView(mode: route.authMode)
                    }
            }
        }
    }
}

/// Root phase `.setup`: SETUP_PROFILE → main (CARD_CREATE or the pending invite).
/// No permissions step: each one is asked when it's first needed — the camera on the first scan,
/// Nearby when Connect opens, notifications once the first card is ready (CARD_CREATE success).
public struct SetupFlowView: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    public init() {}

    public var body: some View {
        NavigationStack {
            SetupProfileView(onContinue: finish)
        }
    }

    private func finish() {
        OnboardingCoordinator.finishSetup(context: modelContext, notificationsGranted: false,
                                          router: router, services: services, store: OnboardingStore())
    }
}

/// Root phase `.deferredWelcome`: DEFERRED_WELCOME → AUTH_SIGNUP.
///
/// "Connect with {first}" stores `invite.cardSlug` as the pending invite (`OnboardingStore`) and
/// pushes sign-in. When onboarding ends — after SETUP_PERMISSIONS, or right after sign-in for an
/// existing account — `OnboardingCoordinator.enterMain` opens
/// `router.open(.scannedCard(ScannedCardPayload(url:slug:)), in: .scan)`; after setup CARD_CREATE
/// is presented on top, so the new user has a card to share back when they tap Connect.
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

#Preview("Language screen") {
    NavigationStack { LanguagePickerView { _ in } }
        .metlyPreview(.signedOut)
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
