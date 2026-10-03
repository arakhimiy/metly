import MetlyCore
import StoreKit
import SwiftUI

/// Marketing content above the StoreKit plan picker: headline tailored to the trigger,
/// "Save 44%" line computed from live prices, benefit list and auto-renew terms.
struct PaywallMarketingHeader: View {
    let content: PaywallContent
    @State private var savings: Savings?

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: content.symbolName)
                    .font(.largeTitle)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text(content.headline)
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(content.message)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if let savings {
                    Text("Save \(savings.percent)% with yearly — just \(savings.monthlyEquivalent) a month")
                        .font(.subheadline.bold())
                        .foregroundStyle(.tint)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(alignment: .leading, spacing: 16) {
                ForEach(content.benefits) { benefit in
                    PaywallBenefitRow(benefit: benefit)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(PaywallContent.renewalTerms)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .task { await loadSavings() }
    }

    private func loadSavings() async {
        guard let products = try? await Product.products(for: ProProduct.allIDs),
              let yearly = products.first(where: { $0.id == ProProduct.yearly.id }),
              let monthly = products.first(where: { $0.id == ProProduct.monthly.id }),
              let percent = PaywallPricing.savingsPercent(yearly: yearly.price, monthly: monthly.price)
        else { return }
        let perMonth = PaywallPricing.monthlyEquivalent(ofYearly: yearly.price).formatted(yearly.priceFormatStyle)
        savings = Savings(percent: percent, monthlyEquivalent: perMonth)
    }

    private struct Savings: Equatable {
        var percent: Int
        var monthlyEquivalent: String
    }
}

/// Icon + title + "Free: …" detail.
struct PaywallBenefitRow: View {
    let benefit: PaywallBenefit
    @ScaledMetric(relativeTo: .title3) private var iconWidth = 32.0

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Image(systemName: benefit.symbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title)
                    .font(.headline)
                Text(benefit.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Paywall header · every trigger") {
    ScrollView {
        VStack(spacing: 32) {
            ForEach([PaywallTrigger.settings, .cardLimit, .followUpLimit, .eventLimit, .proTemplate, .proPalette, .eventExport], id: \.self) { trigger in
                PaywallMarketingHeader(content: PaywallContent(trigger: trigger))
                Divider()
            }
        }
    }
}
