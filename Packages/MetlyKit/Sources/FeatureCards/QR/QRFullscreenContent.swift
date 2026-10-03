import MetlyCore
import MetlyData
import MetlyDesign
import SwiftUI

/// QR_FULLSCREEN body: owner, QR plate, card chooser, Offline QR, Connect Nearby / Share.
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
        Form {
            Section {
                QRHeroView(fullName: profile?.fullName ?? card.name, role: role, mode: mode,
                           isPaused: profile?.linksPaused == true, onResume: resumeLinks)
            }
            .listRowBackground(Color.clear)

            if cards.count > 1 {
                Section("Card") {
                    CardChooser(cards: cards, selection: $selectedCardID)
                }
            }

            Section {
                Toggle(isOn: offlineBinding(mode: mode)) {
                    Label("Offline QR", systemImage: "wifi.slash")
                }
                .disabled(card.url == nil)
            } footer: {
                Text(card.url == nil
                     ? "Your card isn’t published yet, so the QR shares your contact details. Works without internet."
                     : "Works without internet. Contact only, no analytics or Connect.")
            }
        }
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
