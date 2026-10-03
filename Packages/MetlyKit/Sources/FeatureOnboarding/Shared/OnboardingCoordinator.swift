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
            enterMain(router: router, store: store, otherwisePresenting: nil)
        }
    }

    /// End of SETUP_PERMISSIONS ("Create My First Card" or "Skip").
    static func finishSetup(context: ModelContext, notificationsGranted: Bool,
                            router: AppRouter, services: AppServices, store: OnboardingStore) {
        if let profile = context.currentProfile() {
            profile.isSetupComplete = true
            profile.markChanged()
            try? context.save()
        }
        services.preferences.hasCompletedOnboarding = true
        store.setupPrefill = nil
        if notificationsGranted {
            UIApplication.shared.registerForRemoteNotifications()
        }
        services.sync.requestSync()
        enterMain(router: router, store: store, otherwisePresenting: .cardCreate(origin: .setup))
    }

    /// Enters the tab bar. A pending deferred invite wins over `cover`: the person the user met
    /// is surfaced as SCANNED_CARD in the Scan tab so they can save/connect right away.
    static func enterMain(router: AppRouter, store: OnboardingStore, otherwisePresenting cover: CoverDestination?) {
        if let slug = store.pendingInviteSlug {
            store.pendingInviteSlug = nil
            router.enterMain()
            router.open(.scannedCard(invitePayload(slug: slug)), in: .scan)
        } else {
            router.enterMain(presenting: cover)
        }
    }

    nonisolated static func invitePayload(slug: String) -> ScannedCardPayload {
        ScannedCardPayload(url: Brand.cardURL(slug: slug), slug: slug)
    }
}
