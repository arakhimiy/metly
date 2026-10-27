import MetlyCore
import MetlyData
import SwiftUI

/// The single global "Pause All Links" switch (SPEC §9 Q5) — mirrors the one in Profile.
struct LinkPauseToggle: View {
    let profile: Profile
    @Environment(AppServices.self) private var services

    var body: some View {
        Toggle(isOn: isPaused) {
            Label("Pause All Links", systemImage: "pause.circle")
        }
    }

    private var isPaused: Binding<Bool> {
        Binding {
            profile.linksPaused
        } set: { paused in
            setPaused(paused)
        }
    }

    private func setPaused(_ paused: Bool) {
        guard profile.linksPaused != paused else { return }
        profile.linksPaused = paused
        profile.markChanged()
        services.sync.requestSync()
    }
}

/// Footer copy shared by every place that shows the pause switch.
enum LinkPauseCopy {
    static let footer = String(localized: "Paused links show an inactive page. Printed QR codes work again when you resume.")
}
