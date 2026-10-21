import Foundation
import MetlyCore
import Testing
@testable import FeatureOnboarding

/// Where onboarding hands over to the tab bar (SETUP_PERMISSIONS end, returning sign-in).
@MainActor
@Suite("Onboarding hand-off to the app")
struct OnboardingHandOffTests {
    private func makeStore(pendingInvite: String? = nil) throws -> OnboardingStore {
        let store = OnboardingStore(defaults: try #require(UserDefaults(suiteName: "test.handoff.\(UUID().uuidString)")))
        store.pendingInviteSlug = pendingInvite
        return store
    }

    @Test("Without an invite, setup ends on Home with CARD_CREATE")
    func plainSetup() throws {
        let store = try makeStore()
        let router = AppRouter(phase: .setup)
        OnboardingCoordinator.enterMain(router: router, store: store, presenting: .cardCreate(origin: .setup))
        #expect(router.phase == .main)
        #expect(router.selectedTab == .home)
        #expect(pushCount(router) == 0)
        #expect(router.presentations == [.cover(.cardCreate(origin: .setup))])
    }

    /// Regression: a brand-new user who tapped "Connect with {first}" on DEFERRED_WELCOME has no card
    /// yet. Setup used to skip CARD_CREATE and open the inviter's card, whose Connect then failed with
    /// "Create a card first". The first card must still be created, with the inviter's card waiting below.
    @Test("A pending invite after setup still creates the first card, then shows the inviter's card")
    func inviteAfterSetupKeepsCardCreate() throws {
        let store = try makeStore(pendingInvite: "jasur-p4y1")
        let router = AppRouter(phase: .setup)
        OnboardingCoordinator.enterMain(router: router, store: store, presenting: .cardCreate(origin: .setup))
        #expect(router.phase == .main)
        #expect(router.presentations == [.cover(.cardCreate(origin: .setup))])
        #expect(router.selectedTab == .scan)
        #expect(router.paths[.scan] == [.scannedCard(OnboardingCoordinator.invitePayload(slug: "jasur-p4y1"))])
        #expect(store.pendingInviteSlug == nil)
    }

    @Test("A returning account with an invite goes straight to the inviter's card, once")
    func returningAccountWithInvite() throws {
        let store = try makeStore(pendingInvite: "jasur-p4y1")
        let router = AppRouter(phase: .onboarding)
        OnboardingCoordinator.enterMain(router: router, store: store, presenting: nil)
        #expect(router.presentations.isEmpty)
        #expect(router.selectedTab == .scan)
        #expect(router.paths[.scan]?.count == 1)

        // Consumed: a second hand-off doesn't open it again.
        OnboardingCoordinator.enterMain(router: router, store: store, presenting: nil)
        #expect(router.selectedTab == .home)
        #expect(pushCount(router) == 0)
    }

    private func pushCount(_ router: AppRouter) -> Int {
        router.paths.values.reduce(0) { $0 + $1.count }
    }
}
