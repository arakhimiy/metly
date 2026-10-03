import MetlyData
import SwiftUI

/// The event's card. While active it is what Connect / QR / Share use, so tapping shows its QR code.
struct EventCardSection: View {
    let event: Event
    let card: Card?
    let profile: Profile?
    let onShowQR: () -> Void

    var body: some View {
        if let card {
            Section {
                if event.isActive {
                    Button(action: onShowQR) {
                        EventCardRow(card: card, profile: profile, caption: "Card to Share", showsQRIcon: true)
                    }
                    .accessibilityHint("Shows the QR code")
                } else {
                    EventCardRow(card: card, profile: profile, caption: "Card Shared", showsQRIcon: false)
                }
            } footer: {
                if event.isActive {
                    Text("Used for Connect, your QR code and sharing until the event ends.")
                }
            }
        }
    }
}

private struct EventCardRow: View {
    let card: Card
    let profile: Profile?
    let caption: String
    let showsQRIcon: Bool

    var body: some View {
        HStack(spacing: 12) {
            EventCardThumbnail(card: card, profile: profile)
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("\(card.name) Card")
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 8)
            if showsQRIcon {
                Image(systemName: "qrcode")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 4)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}
