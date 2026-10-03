import FeatureOnboarding
import MetlyCore
import MetlyData
import MetlyDesign
import SwiftData
import SwiftUI

/// Switches between the root phases (SPEC §2.1).
struct RootView: View {
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
        .toastHost()
        .task { await bootstrap() }
    }

    private func bootstrap() async {
        guard router.phase == .launching else { return }
        let profile = modelContext.currentProfile()
        if services.auth.isSignedIn, let profile {
            router.phase = profile.isSetupComplete ? .main : .setup
            services.sync.requestSync()
        } else if !services.preferences.hasCompletedOnboarding, let invite = await services.deferredLinks.claimPendingInvite() {
            router.phase = .deferredWelcome(invite)
        } else {
            router.phase = .onboarding
        }
    }
}
