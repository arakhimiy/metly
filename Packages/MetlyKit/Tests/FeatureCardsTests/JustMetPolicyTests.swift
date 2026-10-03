import Foundation
import MetlyCore
import Testing
@testable import FeatureCards

struct JustMetPolicyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func qrMustBeVisibleForMoreThanTwoSeconds() {
        #expect(!JustMetPolicy.shouldPromptAfterQR(shownAt: now.addingTimeInterval(-1.5), now: now, lastPromptAt: nil))
        #expect(!JustMetPolicy.shouldPromptAfterQR(shownAt: now.addingTimeInterval(-2), now: now, lastPromptAt: nil))
        #expect(JustMetPolicy.shouldPromptAfterQR(shownAt: now.addingTimeInterval(-2.5), now: now, lastPromptAt: nil))
    }

    @Test func atMostOncePerTenMinutes() {
        let shownAt = now.addingTimeInterval(-30)
        #expect(!JustMetPolicy.shouldPromptAfterQR(shownAt: shownAt, now: now, lastPromptAt: now.addingTimeInterval(-60)))
        #expect(!JustMetPolicy.shouldPromptAfterQR(shownAt: shownAt, now: now, lastPromptAt: now.addingTimeInterval(-599)))
        #expect(JustMetPolicy.shouldPromptAfterQR(shownAt: shownAt, now: now, lastPromptAt: now.addingTimeInterval(-600)))
    }

    @Test func clockMovedBackDoesNotBlockForever() {
        #expect(!JustMetPolicy.isCoolingDown(lastPromptAt: now.addingTimeInterval(3600), now: now))
    }

    @Test func shareNeedsAShareAction() {
        #expect(!JustMetPolicy.shouldPromptAfterShare(didShare: false, now: now, lastPromptAt: nil))
        #expect(JustMetPolicy.shouldPromptAfterShare(didShare: true, now: now, lastPromptAt: nil))
        #expect(!JustMetPolicy.shouldPromptAfterShare(didShare: true, now: now, lastPromptAt: now.addingTimeInterval(-120)))
    }

    @MainActor
    @Test func prompterRecordsOnlyWhenItOffersTheSheet() {
        let preferences = makePreferences()

        // Too short: nothing recorded.
        #expect(!JustMetPrompter.claimAfterQR(shownAt: now.addingTimeInterval(-1), preferences: preferences, now: now))
        #expect(preferences.lastQRShownAt == nil)

        // Offered: the rate-limit anchor is stored.
        #expect(JustMetPrompter.claimAfterQR(shownAt: now.addingTimeInterval(-5), preferences: preferences, now: now))
        #expect(preferences.lastQRShownAt == now)

        // A share 3 minutes later is inside the cooldown and doesn't move the anchor.
        let later = now.addingTimeInterval(180)
        #expect(!JustMetPrompter.claimAfterShare(didShare: true, preferences: preferences, now: later))
        #expect(preferences.lastQRShownAt == now)

        // 11 minutes later it may ask again.
        let muchLater = now.addingTimeInterval(660)
        #expect(JustMetPrompter.claimAfterShare(didShare: true, preferences: preferences, now: muchLater))
        #expect(preferences.lastQRShownAt == muchLater)
    }
}
