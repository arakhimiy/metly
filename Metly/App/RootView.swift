import FeatureOnboarding
import MetlyCore
import MetlyData
import MetlyDesign
import StoreKit
import SwiftData
import SwiftUI

/// Switches between the root phases (SPEC §2.1).
struct RootView: View {
    /// Sign in with Apple revocation check (true = still valid).
    let checkAppleCredential: () async -> Bool
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext
    @Environment(\.requestReview) private var requestReview
    /// Bumped by `AppLanguage.didChangeNotification`; keys the whole tree so every screen re-reads its strings.
    @State private var language = AppLanguage.current

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
        // Language picked in the app (first screen or Settings › Language): rebuild every screen in
        // it at once. `.id` re-runs every `String(localized:)` against `AppLanguage`'s bundle; the
        // locale drives `Text` keys, dates and numbers. Here, keyed on local state fed by a
        // notification, which re-renders reliably (an @Observable read here did not).
        .environment(\.locale, Locale(identifier: AppLanguage.localeIdentifier))
        .id(language)
        .onReceive(NotificationCenter.default.publisher(for: AppLanguage.didChangeNotification)) { _ in
            language = AppLanguage.current
        }
        // After onboarding: ask for a rating once the first card is made and its cover has closed,
        // when the person just finished something (Apple: ask at a natural pause, not at launch).
        .onChange(of: router.presentations.isEmpty) { _, nothingPresented in
            guard nothingPresented, router.phase == .main, services.preferences.reviewPromptPending else { return }
            services.preferences.reviewPromptPending = false
            Task {
                try? await Task.sleep(for: .seconds(1))
                requestReview()
            }
        }
        .animation(.default, value: router.phase)
        .toastHost(level: 0)
        .task { await bootstrap() }
        // Session expired / Apple ID revoked while running: back to sign-in, but keep local data —
        // unsynced offline edits survive, and signing in as a different account wipes first.
        .onChange(of: services.auth.isSignedIn) { _, signedIn in
            guard !signedIn, router.phase == .main || router.phase == .setup else { return }
            router.signedOut()
        }
    }

    /// Picks the first screen without waiting on the network (cold launch used to sit on a blank
    /// screen for seconds). Slow checks run after the UI is up.
    private func bootstrap() async {
        guard router.phase == .launching else { return }
        if services.auth.isSignedIn {
            let profile = modelContext.currentProfile()
            // A returning account whose profile hasn't been pulled yet must not re-enter setup
            // (saving SETUP_PROFILE would create a second Profile record).
            let setupDone = profile?.isSetupComplete == true || services.preferences.hasCompletedOnboarding
            router.phase = setupDone ? .main : .setup
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
