import MetlyCore
import StoreKit
import SwiftUI

/// PAYWALL cover (SPEC §2.5.37) — native `SubscriptionStoreView` with trigger-specific marketing.
/// Dismisses itself (back to the originating route) after a successful purchase. When the plans
/// can't be loaded (offline, no products in the storefront) the marketing stays on screen with
/// Try Again and Restore Purchases instead of StoreKit's bare "Subscription Unavailable".
struct PaywallScreen: View {
    let trigger: PaywallTrigger
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var availability: PaywallAvailability
    @State private var loadAttempt = 0
    @State private var isLoading = false
    @State private var isRestoring = false
    @State private var failure: Failure?
    @State private var isShowingFailure = false
    @State private var purchaseCount = 0
    private let loadsProducts: Bool

    /// `previewAvailability` shows a fixed state without asking the App Store (previews).
    init(trigger: PaywallTrigger, previewAvailability: PaywallAvailability? = nil) {
        self.trigger = trigger
        _availability = State(initialValue: previewAvailability ?? .loading)
        loadsProducts = previewAvailability == nil
    }

    var body: some View {
        NavigationStack {
            Group {
                switch availability {
                case .loading, .available:
                    storeView
                case .unavailable:
                    PaywallUnavailableView(content: PaywallContent(trigger: trigger),
                                           isRetrying: isLoading,
                                           isRestoring: isRestoring,
                                           onRetry: retry, onRestore: restorePurchases)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", action: close)
                }
            }
        }
        .sensoryFeedback(.success, trigger: purchaseCount)
        .alert(failure?.title ?? "", isPresented: $isShowingFailure, presenting: failure) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        .task(id: loadAttempt) { await loadProducts() }
        .onDisappear(perform: refreshEntitlements)
    }

    private var storeView: some View {
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
    }

    // MARK: Products

    private func loadProducts() async {
        guard loadsProducts else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let products = try await Product.products(for: ProProduct.allIDs)
            availability = PaywallAvailability(loadedProductIDs: products.map(\.id))
        } catch is CancellationError {
            return
        } catch {
            availability = .unavailable
        }
    }

    private func retry() {
        loadAttempt += 1
    }

    // MARK: Actions

    private func close() {
        router.dismiss()
    }

    /// Restores made inside the store view don't arrive as purchases — re-read entitlements on the way out.
    private func refreshEntitlements() {
        let services = services
        Task { await SubscriptionManager.refreshEntitlements(services: services) }
    }

    /// Restore Purchases from the unavailable state (the store view has its own button).
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
                    router.dismiss()
                    router.showToast(String(localized: "Purchases Restored"), systemImage: "checkmark.circle")
                } else {
                    router.showToast(String(localized: "No purchases to restore"), systemImage: "info.circle")
                }
            } catch StoreKitError.userCancelled {
                // The user dismissed the App Store sign-in.
            } catch {
                show(Failure(title: String(localized: "Couldn’t Restore Purchases"), message: error.localizedDescription))
            }
        }
    }

    private func handlePurchase(_ product: Product, _ result: Result<Product.PurchaseResult, any Error>) async {
        switch result {
        case .success(let purchase):
            switch purchase {
            case .success(let verification):
                if await SubscriptionManager.processPurchase(verification, services: services) {
                    purchaseCount += 1
                    router.dismiss()
                    router.showToast(String(localized: "Welcome to \(Brand.proName)"), systemImage: "crown.fill")
                } else {
                    show(.purchase(String(localized: "The App Store couldn’t verify this purchase. Try Restore Purchases, or contact support if this keeps happening.")))
                }
            case .pending:
                router.showToast(String(localized: "Waiting for Approval"), systemImage: "hourglass")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        case .failure(let error):
            show(.purchase(error.localizedDescription))
        }
    }

    private func show(_ failure: Failure) {
        self.failure = failure
        isShowingFailure = true
    }

    private struct Failure: Equatable {
        var title: String
        var message: String

        static func purchase(_ message: String) -> Failure {
            Failure(title: String(localized: "Purchase Failed"), message: message)
        }
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

#Preview("Paywall · Plans unavailable") {
    PaywallScreen(trigger: .followUpLimit, previewAvailability: .unavailable)
        .metlyPreview(.full)
}

#Preview("Paywall · Plans unavailable, dark, large text") {
    PaywallScreen(trigger: .cardLimit, previewAvailability: .unavailable)
        .metlyPreview(.full)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}
