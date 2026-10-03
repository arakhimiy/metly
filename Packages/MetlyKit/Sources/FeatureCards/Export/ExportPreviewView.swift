import MetlyCardKit
import MetlyCore
import SwiftUI

/// The output of the current format: the rendered PNG, the PDF's first page, the Wallet pass
/// mock-up or the Lock Screen wallpaper with a clock on top.
struct ExportPreviewView: View {
    let tab: CardExportTab
    let rendered: RenderedExport?
    let isRendering: Bool
    let design: CardDesign
    /// `.public` content — what the export really contains.
    let content: CardFaceContent
    let cardName: String

    var body: some View {
        // A render of another format (just switched tabs) is not shown in this frame.
        let rendered = rendered?.output.tab == tab ? rendered : nil
        Group {
            switch tab {
            case .wallet:
                WalletPassPreview(design: design, content: content, cardName: cardName)
            case .lockScreen:
                LockScreenPreview(image: rendered?.previewImage, design: design)
            case .image, .pdf:
                RenderedImagePreview(image: rendered?.previewImage, isPage: tab == .pdf)
            }
        }
        .opacity(isRendering ? 0.5 : 1)
        .overlay {
            if isRendering { ProgressView() }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(.isImage)
    }

    private var accessibilityLabel: String {
        switch tab {
        case .image: "Preview of the card image"
        case .pdf: "Preview of the print-ready PDF"
        case .wallet: "Preview of the Apple Wallet pass"
        case .lockScreen: "Preview of the Lock Screen wallpaper"
        }
    }
}

/// PNG export or PDF page thumbnail.
private struct RenderedImagePreview: View {
    let image: UIImage?
    let isPage: Bool

    var body: some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
                .frame(maxWidth: isPage ? 260 : 380, maxHeight: isPage ? 340 : 260)
        } else {
            Color.clear
                .aspectRatio(isPage ? 0.71 : CardFaceView.aspectRatio, contentMode: .fit)
                .frame(maxWidth: isPage ? 240 : 380)
        }
    }
}

/// The wallpaper in a phone-like frame with the date and time where the Lock Screen clock sits.
private struct LockScreenPreview: View {
    let image: UIImage?
    let design: CardDesign

    var body: some View {
        ZStack(alignment: .top) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color.clear.aspectRatio(1206.0 / 2622.0, contentMode: .fit)
            }
            VStack(spacing: 0) {
                Text(Date.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.caption.weight(.semibold))
                Text(Date.now, format: .dateTime.hour().minute())
                    .font(.largeTitle.bold())
                    .fontDesign(.rounded)
            }
            .foregroundStyle(design.colors.foreground.color)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(.top, 28)
        }
        .clipShape(.rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28).strokeBorder(.separator, lineWidth: 1)
        }
        .frame(maxHeight: 400)
    }
}
