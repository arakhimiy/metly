import MetlyCore
import SwiftUI

/// "Tanishly Pro" row showing the current plan → SETTINGS_SUBSCRIPTION.
struct ProPlanSection: View {
    @Environment(AppServices.self) private var services

    var body: some View {
        let entitlements = services.entitlements
        Section {
            NavigationLink(value: PushDestination.settingsSubscription) {
                LabeledContent {
                    Text(PlanDescription.title(isPro: entitlements.isPro, productID: entitlements.productID))
                } label: {
                    SettingsRowLabel(verbatim: Brand.proName, systemImage: "crown.fill", color: .orange)
                }
            }
        }
    }
}
