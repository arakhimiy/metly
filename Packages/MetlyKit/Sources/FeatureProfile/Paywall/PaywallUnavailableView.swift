import MetlyCore
import MetlyDesign
import SwiftUI

/// Whether the Pro plans could be loaded from the App Store.
nonisolated enum PaywallAvailability: Equatable, Sendable {
    /// First fetch still running — `SubscriptionStoreView` shows its own placeholder meanwhile.
    case loading
    case available
    /// No Pro product came back (no StoreKit configuration, storefront without the products) or
    /// the request failed (offline). `SubscriptionStoreView` would only say "Subscription Unavailable".
    case unavailable

    init(loadedProductIDs: [String]) {
        self = loadedProductIDs.contains { ProProduct(productID: $0) != nil } ? .available : .unavailable
    }
}

/// PAYWALL when the plans can't be loaded: the trigger's marketing header stays, with
/// Try Again (re-fetches the products) and Restore Purchases.
struct PaywallUnavailableView: View {
    let content: PaywallContent
    let isRetrying: Bool
    let isRestoring: Bool
    let onRetry: () -> Void
    let onRestore: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                PaywallMarketingHeader(content: content)

                ContentUnavailableView {
                    Label("Plans Unavailable", systemImage: "exclamationmark.icloud")
                } description: {
                    Text("\(Brand.proName) plans couldn’t be loaded from the App Store. Check your connection and try again.")
                } actions: {
                    Button(action: onRetry) {
                        if isRetrying {
                            ProgressView()
                        } else {
                            Text("Try Again")
                        }
                    }
                    .prominentButtonStyle()
                    .controlSize(.large)
                    .disabled(isRetrying)

                    Button(action: onRestore) {
                        if isRestoring {
                            ProgressView()
                        } else {
                            Text("Restore Purchases")
                        }
                    }
                    .disabled(isRestoring)
                }

                HStack(spacing: 16) {
                    Link("Terms of Use", destination: Brand.termsURL)
                    Link("Privacy Policy", destination: Brand.privacyURL)
                }
                .font(.footnote)
                .padding(.bottom, 16)
            }
        }
    }
}
