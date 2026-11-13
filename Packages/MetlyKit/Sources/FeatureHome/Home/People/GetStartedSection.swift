import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// Empty account (no connections yet): the Recent empty copy (SPEC §7.4) plus ways to meet someone.
struct GetStartedSection: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            // Show QR lives in Home's toolbar, so the ways to meet someone here are Connect and Scan.
            EmptyStateView(.connections, title: "No Connections Yet",
                           message: "People you connect with show up here. Open Connect at your next event.",
                           style: .inline) {
                Button("Open Connect", systemImage: "dot.radiowaves.left.and.right", action: openConnect)
                    .subtleButtonStyle()
                Button("Scan a Card", systemImage: "qrcode.viewfinder", action: scan)
                    .subtleButtonStyle()
            }
        } header: {
            HomeSectionHeader(Text("Recent"))
        }
        .headerProminence(.increased)
    }

    private func openConnect() {
        router.present(.connect(cardID: nil))
    }

    private func scan() {
        router.select(.scan)
    }
}
