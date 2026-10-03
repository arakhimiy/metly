import MetlyCore
import MetlyData
import SwiftUI

/// "Sharing": Pause All Links (single global switch), Preview Public Page, Widgets.
struct SharingSection: View {
    let profile: Profile
    let cards: [Card]
    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @State private var browserPage: BrowserPage?

    var body: some View {
        Section {
            Toggle(isOn: profile.editor.binding(\.linksPaused, didEdit: linksPausedHandler())) {
                SettingsRowLabel("Pause All Links", systemImage: "pause.fill", color: .orange)
            }

            Button(action: previewPublicPage) {
                SettingsRowLabel("Preview Public Page", systemImage: "safari.fill", color: .blue)
            }
            .disabled(defaultCardURL == nil)
            .inAppBrowser($browserPage)

            NavigationLink(value: PushDestination.widgetsGallery) {
                SettingsRowLabel("Widgets", systemImage: "square.grid.2x2.fill", color: .purple)
            }
        } header: {
            Text("Sharing")
        } footer: {
            Text(footer)
        }
    }

    /// The default card's public page (Q6: each card has its own page; Profile previews the default one).
    private var defaultCardURL: URL? {
        let summaries = cards.map { CardSummary(id: $0.id, sortOrder: $0.sortOrder) }
        let defaultID = CardManagement.effectiveDefaultID(cards: summaries, defaultID: profile.defaultCardID)
        return cards.first { $0.id == defaultID }?.url
    }

    private var footer: String {
        var text = "Paused links show an inactive page. Printed QR codes work again when you resume."
        if defaultCardURL == nil {
            text += " Your public page appears once your default card is published."
        }
        return text
    }

    /// Toast + sync after the user flips the switch (captures only the Sendable router/services).
    private func linksPausedHandler() -> @MainActor @Sendable (Bool) -> Void {
        let router = router
        let services = services
        return { paused in
            services.sync.requestSync()
            router.showToast(paused ? "Links Paused" : "Links Resumed", systemImage: paused ? "pause.circle" : "play.circle")
        }
    }

    private func previewPublicPage() {
        guard let defaultCardURL else { return }
        browserPage = BrowserPage(url: defaultCardURL)
    }
}
