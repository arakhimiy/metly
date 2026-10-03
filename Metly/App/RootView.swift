import FeatureOnboarding
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// Switches between the root phases (SPEC §2.1).
struct RootView: View {
    /// Sign in with Apple revocation check (true = still valid).
    let checkAppleCredential: () async -> Bool
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            switch router.phase {
            case .launching:
                Color(.systemBackground)
            case .onboarding:
                OnboardingFlowView()
            case .setup:
                SetupFlowView()
            case .deferredWelcome(let invite):
                DeferredWelcomeView(invite: invite)
            case .main:
                MainTabView()
            }
        }
        .animation(.default, value: router.phase)
        .toastHost(level: 0)
        .task { await bootstrap() }
        // Session expired / Apple ID revoked while running.
        .onChange(of: services.auth.isSignedIn) { _, signedIn in
            guard !signedIn, router.phase == .main || router.phase == .setup else { return }
            router.signedOut()
            Task { await services.auth.signOut() }
        }
    }

    private func bootstrap() async {
        guard router.phase == .launching else { return }
        if services.auth.isSignedIn {
            guard await checkAppleCredential() else {
                router.signedOut()
                await services.auth.signOut()
                return
            }
            let profile = modelContext.currentProfile()
            router.phase = profile?.isSetupComplete == true ? .main : .setup
            services.sync.requestSync()
        } else if !services.preferences.hasCompletedOnboarding, let invite = await services.deferredLinks.claimPendingInvite() {
            router.phase = .deferredWelcome(invite)
        } else {
            router.phase = .onboarding
        }
    }
}
