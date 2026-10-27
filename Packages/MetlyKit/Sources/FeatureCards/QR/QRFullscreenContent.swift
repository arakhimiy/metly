import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// QR_FULLSCREEN body: owner, card chooser, QR plate, scan caption, Offline QR, Connect Nearby / Share.
///
/// At default text sizes the whole screen fits without scrolling (iPhone SE included): the code takes
/// the height that is left, between 150 and 300 pt. At large accessibility sizes the same layout
/// scrolls instead of shrinking the code below a comfortably scannable size.
struct QRFullscreenContent: View {
    let card: Card
    let cards: [Card]
    let profile: Profile?
    @Binding var selectedCardID: UUID
    @Binding var prefersOffline: Bool?
    let onConnect: () -> Void
    let onShare: () -> Void

    @Environment(AppServices.self) private var services

    var body: some View {
        let mode = QRCodeMode.resolve(url: card.url, isOnline: services.network.isOnline,
                                      prefersOffline: prefersOffline,
                                      publicContent: CardContentFactory.shareable(card, profile: profile))
        ViewThatFits(in: .vertical) {
            layout(mode: mode, sizing: .fillsRemainingHeight)
            ScrollView {
                layout(mode: mode, sizing: .full)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .bottomActionBar {
            ActionButtonStack {
                Button(action: onShare) {
                    Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
            } secondary: {
                Button(action: onConnect) {
                    Label("Connect Nearby", systemImage: "dot.radiowaves.left.and.right").frame(maxWidth: .infinity)
                }
                .secondaryButtonStyle()
            }
        }
    }

    private func layout(mode: QRCodeMode, sizing: QRCodePlate.Sizing) -> some View {
        VStack(spacing: 16) {
            QROwnerHeader(fullName: profile?.fullName ?? card.name, role: role)

            if cards.count > 1 {
                CardChooser(cards: cards, selection: $selectedCardID)
                    .frame(maxWidth: 360)
            }

            QRCodePlate(mode: mode, isPaused: profile?.linksPaused == true, sizing: sizing, onResume: resumeLinks)

            QRScanCaption(mode: mode)

            OfflineQRToggle(isOn: offlineBinding(mode: mode), isEnabled: card.url != nil,
                            footnote: card.url == nil
                                ? String(localized: "Your card isn’t published yet, so the QR shares your contact details.")
                                : String(localized: "Works without internet. Contact only, no analytics or Connect."))
                .frame(maxWidth: 480)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    private var role: String {
        guard let profile else { return "" }
        return [profile.jobTitle, profile.company].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func offlineBinding(mode: QRCodeMode) -> Binding<Bool> {
        Binding {
            mode.isOffline
        } set: { isOn in
            prefersOffline = isOn
        }
    }

    private func resumeLinks() {
        guard let profile else { return }
        profile.linksPaused = false
        profile.markChanged()
        services.sync.requestSync()
    }
}

/// "Offline QR" switch in a single grouped row, its explanation as the subtitle.
struct OfflineQRToggle: View {
    @Binding var isOn: Bool
    let isEnabled: Bool
    let footnote: String

    var body: some View {
        Toggle(isOn: $isOn) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Offline QR")
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "wifi.slash")
            }
        }
        .disabled(!isEnabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

/// Segmented card picker (a menu once there are too many names for a segmented control).
struct CardChooser: View {
    let cards: [Card]
    @Binding var selection: UUID

    var body: some View {
        if cards.count <= 3 {
            picker.pickerStyle(.segmented).labelsHidden()
        } else {
            picker.pickerStyle(.menu)
        }
    }

    private var picker: some View {
        Picker("Card", selection: $selection) {
            ForEach(cards) { card in
                Text(card.name).tag(card.id)
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}
