import Foundation
import Testing
@testable import FeatureProfile

@Suite("Entitlement mapping")
struct EntitlementMapperTests {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func record(
        _ product: ProProduct = .yearly,
        expiresIn days: Double? = 30,
        state: SubscriptionRecord.RenewalState? = .subscribed,
        willAutoRenew: Bool? = true,
        renewalInDays: Double? = nil,
        revoked: Bool = false,
        upgraded: Bool = false,
        graceEndsIn graceDays: Double? = nil
    ) -> SubscriptionRecord {
        SubscriptionRecord(
            productID: product.id,
            purchaseDate: now.addingTimeInterval(-86_400 * 10),
            expirationDate: days.map { now.addingTimeInterval(86_400 * $0) },
            revocationDate: revoked ? now.addingTimeInterval(-60) : nil,
            isUpgraded: upgraded,
            state: state,
            willAutoRenew: willAutoRenew,
            renewalDate: renewalInDays.map { now.addingTimeInterval(86_400 * $0) },
            gracePeriodExpirationDate: graceDays.map { now.addingTimeInterval(86_400 * $0) }
        )
    }

    @Test func noRecordsMeansFree() {
        #expect(EntitlementMapper.snapshot(from: [], now: now) == .free)
    }

    @Test func activeYearlySubscriptionIsPro() {
        let snapshot = EntitlementMapper.snapshot(from: [record(renewalInDays: 30)], now: now)
        #expect(snapshot.isPro)
        #expect(snapshot.productID == ProProduct.yearly.id)
        #expect(snapshot.willRenew)
        #expect(snapshot.renewsAt == now.addingTimeInterval(86_400 * 30))
    }

    @Test func renewalDateFallsBackToExpiration() {
        let snapshot = EntitlementMapper.snapshot(from: [record(expiresIn: 12, renewalInDays: nil)], now: now)
        #expect(snapshot.renewsAt == now.addingTimeInterval(86_400 * 12))
    }

    @Test func canceledSubscriptionStaysProUntilItExpires() {
        let snapshot = EntitlementMapper.snapshot(from: [record(.monthly, expiresIn: 5, willAutoRenew: false)], now: now)
        #expect(snapshot.isPro)
        #expect(!snapshot.willRenew)
        #expect(snapshot.productID == ProProduct.monthly.id)
    }

    @Test(arguments: [SubscriptionRecord.RenewalState.expired, .revoked, .inBillingRetryPeriod])
    func inactiveStatesAreFree(state: SubscriptionRecord.RenewalState) {
        #expect(!EntitlementMapper.snapshot(from: [record(state: state)], now: now).isPro)
    }

    @Test func revokedTransactionIsFreeEvenIfSubscribed() {
        #expect(!EntitlementMapper.snapshot(from: [record(revoked: true)], now: now).isPro)
    }

    @Test func upgradedTransactionIsIgnored() {
        let snapshot = EntitlementMapper.snapshot(from: [record(.monthly, upgraded: true), record(.yearly)], now: now)
        #expect(snapshot.productID == ProProduct.yearly.id)
    }

    @Test func gracePeriodKeepsProEvenAfterExpiry() {
        let grace = record(expiresIn: -2, state: .inGracePeriod, graceEndsIn: 4)
        let snapshot = EntitlementMapper.snapshot(from: [grace], now: now)
        #expect(snapshot.isPro)
        #expect(snapshot.renewsAt == now.addingTimeInterval(86_400 * 4))
    }

    @Test func endedGracePeriodIsFree() {
        let grace = record(expiresIn: -10, state: .inGracePeriod, graceEndsIn: -1)
        #expect(!EntitlementMapper.snapshot(from: [grace], now: now).isPro)
    }

    @Test func unknownStatusUsesTransactionExpiry() {
        #expect(EntitlementMapper.snapshot(from: [record(expiresIn: 3, state: nil, willAutoRenew: nil)], now: now).isPro)
        #expect(!EntitlementMapper.snapshot(from: [record(expiresIn: -1, state: nil, willAutoRenew: nil)], now: now).isPro)
    }

    @Test func unknownWillRenewIsTreatedAsNotRenewing() {
        #expect(!EntitlementMapper.snapshot(from: [record(state: nil, willAutoRenew: nil)], now: now).willRenew)
    }

    @Test func foreignProductsNeverGrantPro() {
        var foreign = record()
        foreign.productID = "app.tanishly.ios.tip.small"
        #expect(!EntitlementMapper.snapshot(from: [foreign], now: now).isPro)
    }

    @Test func longestLastingSubscriptionWins() {
        let monthly = record(.monthly, expiresIn: 20)
        let yearly = record(.yearly, expiresIn: 300)
        #expect(EntitlementMapper.snapshot(from: [monthly, yearly], now: now).productID == ProProduct.yearly.id)
        #expect(EntitlementMapper.snapshot(from: [yearly, monthly], now: now).productID == ProProduct.yearly.id)
    }

    @Test func planTitles() {
        #expect(PlanDescription.title(isPro: false, productID: ProProduct.yearly.id) == "Free")
        #expect(PlanDescription.title(isPro: true, productID: ProProduct.yearly.id) == "Pro · Yearly")
        #expect(PlanDescription.title(isPro: true, productID: ProProduct.monthly.id) == "Pro · Monthly")
        #expect(PlanDescription.title(isPro: true, productID: nil) == "Pro")
    }

    @Test func usageCopy() {
        #expect(PlanDescription.usage(1, limit: 2) == "1 of 2")
        #expect(PlanDescription.usage(7, limit: nil) == "7 · Unlimited")
    }

    @Test func productIDsMatchTheStoreKitConfiguration() {
        #expect(ProProduct.allIDs == ["app.tanishly.ios.pro.yearly", "app.tanishly.ios.pro.monthly"])
        #expect(ProProduct(productID: "app.tanishly.ios.pro.monthly") == .monthly)
        #expect(ProProduct(productID: nil) == nil)
    }
}
