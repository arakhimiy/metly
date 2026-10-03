#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// QR_FULLSCREEN (Appendix A #15, #16) and SHARE_SHEET (#17) states.

#Preview("QR · online") {
    QRFullscreenView(cardID: PreviewStore.workCardID)
        .metlyPreview(.full)
}

#Preview("QR · offline (vCard)") {
    QRFullscreenView(cardID: PreviewStore.workCardID)
        .metlyPreview(.full, online: false)
}

#Preview("QR · not published yet") {
    PreviewPrepared(prepare: { PreviewStore.unpublish(PreviewStore.workCardID, in: $0) }) {
        QRFullscreenView(cardID: PreviewStore.workCardID)
    }
    .metlyPreview(.empty)
}

#Preview("QR · links paused") {
    PreviewPrepared(prepare: PreviewStore.pauseLinks) {
        QRFullscreenView(cardID: PreviewStore.workCardID)
    }
    .metlyPreview(.full)
}

#Preview("QR · dark, accessibility text") {
    QRFullscreenView(cardID: PreviewStore.personalCardID)
        .metlyPreview(.full)
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility2)
}

#Preview("Share · links live") {
    Color.clear.sheet(isPresented: .constant(true)) {
        ShareCardSheet(cardID: PreviewStore.workCardID)
    }
    .metlyPreview(.full)
}

#Preview("Share · links paused") {
    PreviewPrepared(prepare: PreviewStore.pauseLinks) {
        Color.clear.sheet(isPresented: .constant(true)) {
            ShareCardSheet(cardID: PreviewStore.workCardID)
        }
    }
    .metlyPreview(.full)
}

#Preview("Share · publishing") {
    PreviewPrepared(prepare: { PreviewStore.unpublish(PreviewStore.workCardID, in: $0) }) {
        Color.clear.sheet(isPresented: .constant(true)) {
            ShareCardSheet(cardID: PreviewStore.workCardID)
        }
    }
    .metlyPreview(.full)
}
#endif
