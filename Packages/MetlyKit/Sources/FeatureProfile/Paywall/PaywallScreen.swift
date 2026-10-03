import MetlyCore
import StoreKit
import SwiftUI

/// PAYWALL cover (SPEC §2.5.37) — native `SubscriptionStoreView` with trigger-specific marketing.
/// Dismisses itself (back to the originating route) after a successful purchase.
struct PaywallScreen: View {
    let trigger: PaywallTrigger
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var errorMessage: String?
    @State private var isShowingError = false
    @State private var purchaseCount = 0

    var body: some View {
        NavigationStack {
            SubscriptionStoreView(productIDs: ProProduct.allIDs) {
                PaywallMarketingHeader(content: PaywallContent(trigger: trigger))
            }
            .subscriptionStoreControlStyle(.prominentPicker)
            .subscriptionStoreButtonLabel(.multiline)
            .storeButton(.visible, for: .restorePurchases, .policies)
            .storeButton(.hidden, for: .cancellation)
            .subscriptionStorePolicyDestination(url: Brand.termsURL, for: .termsOfService)
            .subscriptionStorePolicyDestination(url: Brand.privacyURL, for: .privacyPolicy)
            .onInAppPurchaseCompletion(perform: handlePurchase)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .sensoryFeedback(.success, trigger: purchaseCount)
        .alert("Purchase Failed", isPresented: $isShowingError, presenting: errorMessage) { _ in
            Button("OK", role: .cancel) {}
        } message: { message in
            Text(message)
        }
        .onDisappear(perform: refreshEntitlements)
    }

    private func close() {
        router.dismiss()
    }

    /// Restores made inside the store view don't arrive as purchases — re-read entitlements on the way out.
    private func refreshEntitlements() {
        let services = services
        Task { await SubscriptionManager.refreshEntitlements(services: services) }
    }

    private func handlePurchase(_ product: Product, _ result: Result<Product.PurchaseResult, any Error>) async {
        switch result {
        case .success(let purchase):
            switch purchase {
            case .success(let verification):
                if await SubscriptionManager.processPurchase(verification, services: services) {
                    purchaseCount += 1
                    router.dismiss()
                    router.showToast("Welcome to \(Brand.proName)", systemImage: "crown.fill")
                } else {
                    show("The App Store couldn’t verify this purchase. Try Restore Purchases, or contact support if this keeps happening.")
                }
            case .pending:
                router.showToast("Waiting for Approval", systemImage: "hourglass")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        case .failure(let error):
            show(error.localizedDescription)
        }
    }

    private func show(_ message: String) {
        errorMessage = message
        isShowingError = true
    }
}

#Preview("Paywall · Settings") {
    PaywallView(trigger: .settings)
        .metlyPreview(.full)
}

#Preview("Paywall · Card limit") {
    PaywallView(trigger: .cardLimit)
        .metlyPreview(.full)
}

#Preview("Paywall · Follow-up limit") {
    PaywallView(trigger: .followUpLimit)
        .metlyPreview(.full)
}

#Preview("Paywall · Event limit") {
    PaywallView(trigger: .eventLimit)
        .metlyPreview(.full)
}

#Preview("Paywall · Pro template") {
    PaywallView(trigger: .proTemplate)
        .metlyPreview(.full)
}

#Preview("Paywall · Pro palette") {
    PaywallView(trigger: .proPalette)
        .metlyPreview(.full)
}

#Preview("Paywall · Event export") {
    PaywallView(trigger: .eventExport)
        .metlyPreview(.full)
}
