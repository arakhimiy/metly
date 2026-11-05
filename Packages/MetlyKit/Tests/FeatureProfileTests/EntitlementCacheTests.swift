import Foundation
import Testing
@testable import FeatureProfile

@Suite("Entitlement cache")
struct EntitlementCacheTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)
    let cache = EntitlementCache(store: UserDefaults(suiteName: "EntitlementCacheTests.\(UUID().uuidString)")!)

    private func pro(renewsIn days: Double?) -> EntitlementSnapshot {
        EntitlementSnapshot(isPro: true, productID: ProProduct.yearly.id,
                            renewsAt: days.map { now.addingTimeInterval(86_400 * $0) }, willRenew: true)
    }

    @Test func keepsProUntilItsPeriodEnds() {
        cache.save(pro(renewsIn: 30))
        #expect(cache.load(now: now) == pro(renewsIn: 30))
        #expect(cache.load(now: now.addingTimeInterval(86_400 * 31)) == nil)
    }

    @Test func proWithoutAnEndDateStays() {
        cache.save(pro(renewsIn: nil))
        #expect(cache.load(now: now)?.isPro == true)
    }

    @Test func freeClearsTheCache() {
        cache.save(pro(renewsIn: 30))
        cache.save(.free)
        #expect(cache.load(now: now) == nil)
    }

    @Test func emptyCacheLoadsNothing() {
        #expect(cache.load(now: now) == nil)
    }
}
