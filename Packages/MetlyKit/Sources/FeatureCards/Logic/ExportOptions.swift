import MetlyCardKit
import MetlyCore

/// Everything chosen on CARD_EXPORT. Each tab keeps its own option so switching tabs doesn't reset it.
nonisolated struct ExportOptions: Hashable, Sendable {
    var tab: CardExportTab
    var scale: ExportScale = .x2
    var corners: ExportCorners = .rounded
    var pdfLayout: ExportPDFLayout = .single
    var device: CardExporter.LockScreenDevice = .iPhone16Pro

    init(tab: CardExportTab) {
        self.tab = tab
    }

    /// The file the current tab produces (Wallet passes come from the server instead).
    var output: ExportOutput? {
        switch tab {
        case .image: .png(scale: scale, corners: corners)
        case .pdf: .pdf(pdfLayout)
        case .wallet: nil
        case .lockScreen: .lockScreen(device)
        }
    }
}

extension CardExportTab {
    nonisolated var title: String {
        switch self {
        case .image: "Image"
        case .pdf: "PDF"
        case .wallet: "Wallet"
        case .lockScreen: "Lock Screen"
        }
    }
}
