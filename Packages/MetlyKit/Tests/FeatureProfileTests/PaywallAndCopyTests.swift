import Foundation
import MetlyCore
import Testing
@testable import FeatureProfile

@Suite("Paywall content & settings copy")
struct PaywallAndCopyTests {
    @Test(arguments: [
        (PaywallTrigger.cardLimit, PaywallBenefit.Kind.cards),
        (.followUpLimit, .followUps),
        (.eventLimit, .events),
        (.proTemplate, .designs),
        (.proPalette, .designs),
        (.eventExport, .eventExport),
    ])
    func triggerBenefitIsListedFirst(trigger: PaywallTrigger, kind: PaywallBenefit.Kind) {
        let content = PaywallContent(trigger: trigger)
        #expect(content.highlighted == kind)
        #expect(content.benefits.first?.kind == kind)
        #expect(content.benefits.count == PaywallBenefit.Kind.allCases.count)
    }

    @Test func settingsTriggerUsesTheProName() {
        let content = PaywallContent(trigger: .settings)
        #expect(content.headline == Brand.proName)
        #expect(content.highlighted == nil)
        #expect(content.benefits.map(\.kind) == PaywallBenefit.Kind.allCases)
    }

    @Test func noAIBenefitsInV1() {
        let titles = PaywallBenefit.Kind.allCases.map { PaywallBenefit.make($0).title.lowercased() }
        #expect(!titles.contains { $0.split(separator: " ").contains("ai") })
    }

    /// No products (StoreKit configuration not active, storefront without them) must show the
    /// marketing + Try Again / Restore state instead of StoreKit's bare "Subscription Unavailable".
    @Test func paywallFallsBackWhenNoProPlanLoads() {
        #expect(PaywallAvailability(loadedProductIDs: []) == .unavailable)
        #expect(PaywallAvailability(loadedProductIDs: ["app.tanishly.ios.tip.small"]) == .unavailable)
        #expect(PaywallAvailability(loadedProductIDs: [ProProduct.monthly.id]) == .available)
        #expect(PaywallAvailability(loadedProductIDs: ProProduct.allIDs) == .available)
    }

    @Test func yearlyPlanSaves44Percent() {
        #expect(PaywallPricing.savingsPercent(yearly: Decimal(string: "19.99")!, monthly: Decimal(string: "2.99")!) == 44)
        #expect(PaywallPricing.savingsPercent(yearly: 40, monthly: 3) == nil)
        #expect(PaywallPricing.savingsPercent(yearly: 10, monthly: 0) == nil)
    }

    @Test func monthlyEquivalentOfYearly() {
        let perMonth = PaywallPricing.monthlyEquivalent(ofYearly: Decimal(string: "19.99")!)
        #expect(abs(NSDecimalNumber(decimal: perMonth).doubleValue - 1.6658) < 0.001)
    }

    @Test func deleteAccountCopyPluralises() {
        #expect(AccountCopy.deleteAccountMessage(cardCount: 2, peopleCount: 6)
            .contains("2 cards with their links and QR codes, and your notes on 6 people"))
        #expect(AccountCopy.deleteAccountMessage(cardCount: 1, peopleCount: 1)
            .contains("1 card with its link and QR code, and your notes on 1 person"))
    }

    @Test func supportMailCarriesVersionAndDevice() throws {
        let info = AppInfo(version: "1.0", build: "42", systemVersion: "iOS 18.2", deviceModel: "iPhone17,1")
        let url = try #require(SupportMail.url(appInfo: info))
        #expect(url.scheme == "mailto")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.path == Brand.supportEmail)
        let body = try #require(components.queryItems?.first { $0.name == "body" }?.value)
        #expect(body.contains("\(Brand.appName) 1.0 (42)"))
        #expect(body.contains("iOS 18.2 · iPhone17,1"))
        #expect(!url.absoluteString.contains(" "))
    }

    @Test func telegramLinkStartsTheReminderBot() throws {
        let token = TelegramLinking.placeholderToken()
        #expect(token.count == 32)
        #expect(token.allSatisfy { $0.isLetter || $0.isNumber })
        let url = try #require(TelegramLinking.startURL(token: token))
        #expect(url.absoluteString == "https://t.me/\(Brand.telegramBot)?start=\(token)")
    }
}
