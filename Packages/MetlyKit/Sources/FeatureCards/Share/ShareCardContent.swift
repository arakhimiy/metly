import MetlyCore
import MetlyData
import SwiftUI
import UIKit

/// SHARE_SHEET list. Feedback stays inline (the app's toast HUD sits under sheets).
struct ShareCardContent: View {
    let card: Card
    let profile: Profile?
    @Binding var didShare: Bool
    let onClose: () -> Void
    let onExport: () -> Void

    @Environment(AppServices.self) private var services
    @Environment(\.walletPassProvider) private var walletPassProvider
    @State private var wallet = WalletAddFlow()
    @State private var copyCount = 0
    @State private var isShowingCopied = false

    var body: some View {
        let status = CardLinkStatus(url: card.url, isOnline: services.network.isOnline)
        NavigationStack {
            List {
                Section {
                    ShareCardHeader(design: card.design, content: CardContentFactory.preview(of: card, profile: profile),
                                    title: title, status: status, isPaused: profile?.linksPaused == true)
                }

                Section {
                    Button(action: { copy(status.url) }) {
                        Label(isShowingCopied ? "Copied" : "Copy Link",
                              systemImage: isShowingCopied ? "checkmark" : "doc.on.doc")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .disabled(status.url == nil)

                    if let url = status.url {
                        ShareLink(item: url, message: Text(ShareCopy.message)) {
                            Label("Share Link…", systemImage: "square.and.arrow.up")
                        }
                        .simultaneousGesture(TapGesture().onEnded { didShare = true })
                    } else {
                        Button("Share Link…", systemImage: "square.and.arrow.up") {}
                            .disabled(true)
                    }
                } footer: {
                    if let explanation = status.explanation {
                        Text(explanation)
                    }
                }

                Section {
                    Button(action: addToWallet) {
                        HStack {
                            Label("Add to Apple Wallet", systemImage: "wallet.pass")
                            Spacer(minLength: 8)
                            if wallet.isLoading { ProgressView() }
                        }
                    }
                    .disabled(wallet.isLoading || status.url == nil)

                    Button("Save Image or PDF", systemImage: "square.and.arrow.down", action: onExport)
                } footer: {
                    if status.url == nil {
                        Text("Apple Wallet becomes available once your card is published.")
                    }
                }

                if let profile {
                    Section {
                        LinkPauseToggle(profile: profile)
                    } footer: {
                        Text(LinkPauseCopy.footer)
                    }
                }
            }
            .navigationTitle("Share Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close", systemImage: "xmark", action: onClose)
                }
            }
        }
        .walletAddFlow(wallet)
        .sensoryFeedback(.success, trigger: copyCount)
        .onChange(of: wallet.addedCount) { didShare = true }
        .task(id: copyCount) { await flashCopied() }
    }

    /// "Aziza Karimova · Work"
    private var title: String {
        guard let name = profile?.fullName, !name.isEmpty else { return "\(card.name) Card" }
        return "\(name) · \(card.name)"
    }

    private func copy(_ url: URL?) {
        guard let url else { return }
        UIPasteboard.general.url = url
        copyCount += 1
        didShare = true
    }

    private func flashCopied() async {
        guard copyCount > 0 else { return }
        isShowingCopied = true
        try? await Task.sleep(for: .seconds(2))
        isShowingCopied = false
    }

    private func addToWallet() {
        let cardID = card.id
        let provider = walletPassProvider
        Task { await wallet.start(cardID: cardID, provider: provider) }
    }
}
