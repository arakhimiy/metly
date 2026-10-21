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

    /// Picks the first screen without waiting on the network (cold launch used to sit on a blank
    /// screen for seconds). Slow checks run after the UI is up.
    private func bootstrap() async {
        guard router.phase == .launching else { return }
        if services.auth.isSignedIn {
            let profile = modelContext.currentProfile()
            router.phase = profile?.isSetupComplete == true ? .main : .setup
            services.sync.requestSync()
            // Apple ID revoked while the app was closed → sign out (async, after first frame).
            if await !checkAppleCredential() {
                router.signedOut()
                await services.auth.signOut()
            }
        } else if !services.preferences.hasCompletedOnboarding,
                  let invite = await claimInvite(timeout: .seconds(1)) {
            router.phase = .deferredWelcome(invite)
        } else {
            router.phase = .onboarding
        }
    }

    /// First launch only: give install attribution a short window, then show onboarding.
    private func claimInvite(timeout: Duration) async -> DeferredInvite? {
        let deferredLinks = services.deferredLinks
        let gate = ResumeOnce()
        return await withCheckedContinuation { continuation in
            Task {
                let invite = await deferredLinks.claimPendingInvite()
                if gate.claim() { continuation.resume(returning: invite) }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if gate.claim() { continuation.resume(returning: nil) }
            }
        }
    }
}

/// Lets exactly one of two racing main-actor tasks resume a continuation.
@MainActor
private final class ResumeOnce {
    private var done = false
    func claim() -> Bool {
        defer { done = true }
        return !done
    }
}
