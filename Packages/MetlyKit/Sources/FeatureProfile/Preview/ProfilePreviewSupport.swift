import Foundation
import MetlyCore
import MetlyData
import SwiftData
import SwiftUI

extension View {
    /// Like `metlyPreview`, but lets a preview tweak the seeded profile and the entitlements first
    /// (empty fields, paused links, a yearly Pro subscription that won't renew…).
    func profilePreview(
        _ seed: PreviewSeed.Variant = .full,
        plan: Plan = .free,
        online: Bool = true,
        configure: (Profile) -> Void = { _ in },
        entitlements configureEntitlements: (Entitlements) -> Void = { _ in }
    ) -> some View {
        let container = MetlyModelContainer.preview(seed)
        if let profile = container.mainContext.currentProfile() {
            configure(profile)
            try? container.mainContext.save()
        }
        let services = AppServices.preview(plan: plan, online: online)
        configureEntitlements(services.entitlements)
        return self
            .modelContainer(container)
            .environment(AppRouter(phase: .main))
            .environment(services)
    }
}

extension Profile {
    /// Preview helper: a Public office line and a Private home line after the mobile.
    func addPreviewPhones() {
        phoneLabel = .mobile
        additionalPhones = [
            LabeledPhone(label: .work, value: "+998 71 200 10 20", privacy: .public),
            LabeledPhone(label: .home, value: "+998 71 255 33 44", privacy: .private),
        ]
    }
}

extension Entitlements {
    /// Preview helper: an active yearly subscription renewing in ~8 months.
    func simulateYearly(willRenew: Bool = true) {
        plan = .pro
        productID = ProProduct.yearly.id
        renewsAt = Calendar.current.date(byAdding: .month, value: 8, to: .now)
        self.willRenew = willRenew
    }
}
