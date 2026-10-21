import MetlyCore

/// CARD_CREATE navigation decisions, kept out of the view so they can be unit-tested with `AppRouter`.
@MainActor
enum CardCreateFlow {
    /// "See Pro" on the Free card-limit alert: the paywall goes *on top of* the wizard (it closes with
    /// `router.dismiss()`), so after a purchase the user is back in CARD_CREATE with their choices
    /// intact instead of on Home — and a limit hit at Publish no longer discards the wizard.
    static func showLimitPaywall(router: AppRouter) {
        router.present(.paywall(trigger: .cardLimit))
    }

    /// Whether the wizard shows the Free card-limit alert when it (re)appears — on open, and again when
    /// the paywall closes without an upgrade. Never once the new card exists (success screen).
    static func needsLimitAlert(canCreate: Bool, hasCreatedCard: Bool) -> Bool {
        !canCreate && !hasCreatedCard
    }
}
