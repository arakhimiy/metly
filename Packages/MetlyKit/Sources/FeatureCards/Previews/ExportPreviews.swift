#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// CARD_EXPORT states (SPEC Appendix A #50, #51): every format.

#Preview("Export · Image") {
    CardExportView(cardID: PreviewStore.workCardID, tab: .image)
        .metlyPreview(.full)
}

#Preview("Export · PDF") {
    CardExportView(cardID: PreviewStore.workCardID, tab: .pdf)
        .metlyPreview(.full)
}

#Preview("Export · Wallet") {
    CardExportView(cardID: PreviewStore.workCardID, tab: .wallet)
        .metlyPreview(.full)
}

#Preview("Export · Wallet (offline)") {
    CardExportView(cardID: PreviewStore.workCardID, tab: .wallet)
        .metlyPreview(.full, online: false)
}

#Preview("Export · Lock Screen") {
    CardExportView(cardID: PreviewStore.personalCardID, tab: .lockScreen)
        .metlyPreview(.full)
}

/// Only the Public office number joins the mobile; the Connections and Private numbers stay off the export.
#Preview("Export · Image, several phones") {
    PreviewPrepared(prepare: {
        PreviewStore.addPhones(in: $0, primaryPrivacy: .public)
        PreviewStore.useDesign(CardDesign(template: .professional, palette: .ink, density: .detailed,
                                          visibleFields: [.phone, .email]),
                               for: PreviewStore.workCardID, in: $0)
    }) {
        CardExportView(cardID: PreviewStore.workCardID, tab: .image)
    }
    .metlyPreview(.full)
}

#Preview("Export · Image, unpublished, dark") {
    PreviewPrepared(prepare: { PreviewStore.unpublish(PreviewStore.workCardID, in: $0) }) {
        CardExportView(cardID: PreviewStore.workCardID, tab: .image)
    }
    .metlyPreview(.full)
    .preferredColorScheme(.dark)
}
#endif
