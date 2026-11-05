import MetlyCore
import MetlyData
import StoreKit
import SwiftData
import SwiftUI

/// SETTINGS_SUBSCRIPTION (SPEC §2.5.19). Cancel / change plan → App Store `manageSubscriptionsSheet` (Q27).
/// Free: Redeem Promo Code opens the App Store's offer code sheet (partner codes from events).
struct SubscriptionSettingsScreen: View {
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Query(Card.live) private var cards: [Card]
    @Query(FollowUp.open) private var openFollowUps: [FollowUp]
    @State private var isManaging = false
    @State private var isRestoring = false
    @State private var isRedeemingCode = false
    @State private var errorMessage: String?
    @State private var isShowingError = false

    var body: some View {
        let entitlements = services.entitlements
        let limits = entitlements.limits

        Form {
            Section("Plan") {
                LabeledContent("Current Plan", value: PlanDescription.title(isPro: entitlements.isPro, productID: entitlements.productID))
                LabeledContent("Cards", value: PlanDescription.usage(cards.count, limit: limits.maxCards))
                LabeledContent("Active Follow-ups", value: PlanDescription.usage(openFollowUps.count, limit: limits.maxOpenFollowUps))
                if entitlements.isPro, let renewsAt = entitlements.renewsAt {
                    LabeledContent(entitlements.willRenew ? "Renews" : "Expires") {
                        Text(renewsAt, format: .dateTime.day().month(.abbreviated).year())
                    }
                }
            }

            if entitlements.isPro {
                Section {
                    Button("Manage Subscription", action: manageSubscription)
                } footer: {
                    Text(manageFooter)
                }
            } else {
                Section {
                    Button("Upgrade to \(Brand.proName)", systemImage: "crown", action: upgrade)
                    Button("Redeem Promo Code", systemImage: "ticket") { isRedeemingCode = true }
                } footer: {
                    Text("Unlimited cards, follow-ups and events, every template and palette, and event export to CSV.")
                }
            }

            Section {
                Button(action: restorePurchases) {
                    HStack {
                        Text("Restore Purchases")
                        Spacer()
                        if isRestoring {
                            ProgressView()
                        }
                    }
                }
                .disabled(isRestoring)
            } footer: {
                Text(AccountCopy.billingFooter)
            }
        }
        .navigationTitle("Subscription")
        .navigationBarTitleDisplayMode(.inline)
        .manageSubscriptionsSheet(isPresented: $isManaging)
        .offerCodeRedemption(isPresented: $isRedeemingCode) { _ in refreshAfterRedeeming() }
        .onChange(of: isManaging) { _, isPresented in
            if !isPresented { refreshAfterManaging() }
        }
        .alert("Couldn’t Restore Purchases", isPresented: $isShowingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }

    private var manageFooter: String {
        let entitlements = services.entitlements
        if !entitlements.willRenew, let renewsAt = entitlements.renewsAt {
            let date = renewsAt.formatted(date: .abbreviated, time: .omitted)
            return String(localized: "Your subscription won’t renew. You keep Pro until \(date). Cards beyond two become read-only after that.")
        }
        return String(localized: "Change your plan or cancel in your App Store account.") + " " + AccountCopy.afterCancelMessage
    }

    // MARK: Actions

    private func upgrade() {
        router.present(.paywall(trigger: .settings))
    }

    private func manageSubscription() {
        isManaging = true
    }

    private func refreshAfterManaging() {
        let services = services
        Task { await SubscriptionManager.refreshEntitlements(services: services) }
    }

    /// A redeemed code also arrives through `Transaction.updates`; re-read now so the plan flips right away.
    private func refreshAfterRedeeming() {
        let services = services
        let router = router
        Task {
            await SubscriptionManager.refreshEntitlements(services: services, verifyWithServer: true)
            if services.entitlements.isPro {
                router.showToast(String(localized: "Welcome to \(Brand.proName)"), systemImage: "crown.fill")
            }
        }
    }

    private func restorePurchases() {
        let services = services
        let router = router
        Task {
            isRestoring = true
            defer { isRestoring = false }
            do {
                try await AppStore.sync()
                await SubscriptionManager.refreshEntitlements(services: services, verifyWithServer: true)
                if services.entitlements.isPro {
                    router.showToast(String(localized: "Purchases Restored"), systemImage: "checkmark.circle")
                } else {
                    router.showToast(String(localized: "No purchases to restore"), systemImage: "info.circle")
                }
            } catch StoreKitError.userCancelled {
                // The user dismissed the App Store sign-in.
            } catch {
                errorMessage = error.localizedDescription
                isShowingError = true
            }
        }
    }
}

#Preview("Subscription · Free") {
    NavigationStack { SubscriptionSettingsScreen() }
        .metlyPreview(.full)
}

#Preview("Subscription · Pro yearly") {
    NavigationStack { SubscriptionSettingsScreen() }
        .profilePreview(plan: .pro, entitlements: { $0.simulateYearly() })
}

#Preview("Subscription · Pro, canceled") {
    NavigationStack { SubscriptionSettingsScreen() }
        .profilePreview(plan: .pro, entitlements: { $0.simulateYearly(willRenew: false) })
}
