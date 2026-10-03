import SwiftUI

/// Menu content for MENU_CARD_ACTIONS: Copy Link · Share… · Show QR Code · Connect Nearby ·
/// Edit Card · Card Settings… · Export… · Set as Default / ✓ Default Card · Delete Card.
struct CardActionsMenu: View {
    let hasLink: Bool
    let isDefault: Bool
    let isReadOnly: Bool
    let perform: (CardAction) -> Void

    var body: some View {
        Section {
            Button("Copy Link", systemImage: "link") { perform(.copyLink) }
                .disabled(!hasLink)
            Button("Share…", systemImage: "square.and.arrow.up") { perform(.share) }
            Button("Show QR Code", systemImage: "qrcode") { perform(.showQR) }
            Button("Connect Nearby", systemImage: "dot.radiowaves.left.and.right") { perform(.connect) }
        }
        Section {
            Button("Edit Card", systemImage: "pencil") { perform(.edit) }
                .disabled(isReadOnly)
            Button("Card Settings…", systemImage: "gearshape") { perform(.settings) }
            Button("Export…", systemImage: "square.and.arrow.down") { perform(.export) }
        }
        Section {
            if isDefault {
                Button("Default Card", systemImage: "checkmark") {}
                    .disabled(true)
            } else {
                Button("Set as Default", systemImage: "star") { perform(.setDefault) }
            }
            Button("Delete Card", systemImage: "trash", role: .destructive) { perform(.delete) }
        }
    }
}
