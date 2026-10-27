import MetlyCore
import MetlyDesign
import SwiftUI

/// Bottom actions per format: Share (file) + Save to Photos / Save to Files / Save Wallpaper,
/// or Apple's "Add to Apple Wallet" button.
struct ExportActionBar: View {
    let tab: CardExportTab
    /// The finished render for the current options (nil while rendering).
    let rendered: RenderedExport?
    let isSaved: Bool
    let walletAvailable: Bool
    let walletAdded: Bool
    let isWalletLoading: Bool
    let onSavePhoto: () -> Void
    let onSaveFiles: () -> Void
    let onAddToWallet: () -> Void

    @ScaledMetric(relativeTo: .body) private var walletButtonHeight: CGFloat = 50

    var body: some View {
        if tab == .wallet {
            VStack(spacing: 8) {
                AddToWalletButton(action: onAddToWallet)
                    .frame(height: walletButtonHeight)
                    .frame(maxWidth: 360)
                    .disabled(!walletAvailable || isWalletLoading)
                    .opacity(walletAvailable ? 1 : 0.4)
                    .accessibilityLabel(Text("Add to Apple Wallet"))
                    .accessibilityAddTraits(.isButton)
                if isWalletLoading {
                    ProgressView()
                } else if walletAdded {
                    Label("Added to Wallet", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else if !walletAvailable {
                    Text("Needs a published card and an internet connection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: .infinity)
        } else {
            ActionButtonStack {
                Button(action: primaryAction) {
                    Label(primaryTitle, systemImage: isSaved ? "checkmark" : primarySymbol)
                        .frame(maxWidth: .infinity)
                }
                .prominentButtonStyle()
                .disabled(rendered == nil || isSaved)
            } secondary: {
                if let rendered {
                    ShareLink(item: rendered.fileURL,
                              preview: SharePreview(rendered.fileName, image: previewImage(rendered))) {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .secondaryButtonStyle()
                } else {
                    Button {} label: {
                        Label("Share", systemImage: "square.and.arrow.up").frame(maxWidth: .infinity)
                    }
                    .secondaryButtonStyle()
                    .disabled(true)
                }
            }
        }
    }

    private var primaryTitle: String {
        switch (tab, isSaved) {
        case (.pdf, false): String(localized: "Save to Files")
        case (.pdf, true): String(localized: "Saved to Files")
        case (.lockScreen, false): String(localized: "Save Wallpaper")
        case (.lockScreen, true): String(localized: "Wallpaper Saved")
        case (_, false): String(localized: "Save to Photos")
        case (_, true): String(localized: "Saved to Photos")
        }
    }

    private var primarySymbol: String {
        tab == .pdf ? "folder" : "photo.badge.arrow.down"
    }

    private func primaryAction() {
        if tab == .pdf { onSaveFiles() } else { onSavePhoto() }
    }

    private func previewImage(_ rendered: RenderedExport) -> Image {
        rendered.previewImage.map { Image(uiImage: $0) } ?? Image(systemName: "doc")
    }
}
