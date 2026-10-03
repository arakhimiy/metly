import MetlyCore
import MetlyData
import SwiftUI

/// Empty account (no connections yet): the Recent empty copy (SPEC §7.4) plus ways to meet someone.
struct GetStartedSection: View {
    let cardToShare: Card?

    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            Text("People you connect with show up here. Open Connect at your next event.")
                .foregroundStyle(.secondary)
            Button("Open Connect", systemImage: "dot.radiowaves.left.and.right", action: openConnect)
            if cardToShare != nil {
                Button("Show My QR Code", systemImage: "qrcode", action: showQR)
            }
            Button("Scan a Card", systemImage: "qrcode.viewfinder", action: scan)
        } header: {
            HomeSectionHeader(Text("Recent"))
        }
        .headerProminence(.increased)
    }

    private func openConnect() {
        router.present(.connect(cardID: nil))
    }

    private func showQR() {
        guard let cardToShare else { return }
        router.present(.qr(cardID: cardToShare.id))
    }

    private func scan() {
        router.select(.scan)
    }
}
