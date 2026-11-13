import MetlyCore
import MetlyData
import SwiftData
import UIKit

/// What a successful sign-in produced, with the provider's name/email as a fallback prefill.
struct SignInOutcome {
    var result: AuthResult
    var provider: AuthProvider
    var suggestedName: String?
    var email: String?
}

/// Root-phase decisions shared by AUTH_SIGNUP, SETUP_PERMISSIONS and DEFERRED_WELCOME.
enum OnboardingCoordinator {
    /// After a successful Apple / Google sign-in.
    static func didSignIn(_ outcome: SignInOutcome, router: AppRouter, services: AppServices, store: OnboardingStore) {
        if outcome.result.needsSetup {
            store.setupPrefill = SetupPrefill(fullName: outcome.suggestedName, email: outcome.email, provider: outcome.provider)
            router.phase = .setup
        } else {
            // Returning account: skip setup entirely.
            store.setupPrefill = nil
            services.preferences.hasCompletedOnboarding = true
            services.sync.requestSync()
            enterMain(router: router, store: store, presenting: nil)
        }
    }

    /// End of setup (SETUP_PROFILE "Continue"). `notificationsGranted` registers for pushes right away.
    static func finishSetup(context: ModelContext, notificationsGranted: Bool,
                            router: AppRouter, services: AppServices, store: OnboardingStore) {
        if let profile = context.currentProfile() {
            profile.isSetupComplete = true
            profile.markChanged()
            try? context.save()
        }
        services.preferences.hasCompletedOnboarding = true
        services.preferences.reviewPromptPending = true   // asked once the first card is made (RootView)
        store.setupPrefill = nil
        if notificationsGranted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        services.sync.requestSync()
        enterMain(router: router, store: store, presenting: .cardCreate(origin: .setup))
    }

    /// Enters the tab bar, presenting `cover` (CARD_CREATE after setup). A pending deferred invite
    /// is surfaced as SCANNED_CARD in the Scan tab — underneath `cover`: a brand-new account has no
    /// card yet, and Connect needs one to share back, so the first card is created before the
    /// inviter's card shows.
    static func enterMain(router: AppRouter, store: OnboardingStore, presenting cover: CoverDestination?) {
        router.enterMain()
        if let slug = store.pendingInviteSlug {
            store.pendingInviteSlug = nil
            router.open(.scannedCard(invitePayload(slug: slug)), in: .scan)
        }
        if let cover {
            router.present(cover)
        }
    }

    nonisolated static func invitePayload(slug: String) -> ScannedCardPayload {
        ScannedCardPayload(url: Brand.cardURL(slug: slug), slug: slug)
    }
}
