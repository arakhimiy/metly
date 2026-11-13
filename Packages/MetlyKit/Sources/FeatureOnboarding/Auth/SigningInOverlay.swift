import MetlyDesign
import SwiftUI

/// Loading HUD shown while the backend exchanges the provider credential.
struct SigningInOverlay: View {
    var body: some View {
        ProgressView("Signing In…")
            .controlSize(.large)
            .padding(24)
            .glassOrMaterial(in: .rect(cornerRadius: 20))
            .accessibilityElement(children: .combine)
            .onAppear {
                AccessibilityNotification.Announcement(String(localized: "Signing In", bundle: .appStrings)).post()
            }
    }
}
