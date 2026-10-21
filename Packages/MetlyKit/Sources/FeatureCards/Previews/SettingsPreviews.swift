#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// CARD_SETTINGS states (SPEC Appendix A #75).

#Preview("Card Settings · two cards (Free)") {
    NavigationStack {
        CardSettingsView(cardID: PreviewStore.workCardID)
    }
    .metlyPreview(.full, plan: .free)
}

#Preview("Card Settings · not default, Pro") {
    NavigationStack {
        CardSettingsView(cardID: PreviewStore.personalCardID)
    }
    .metlyPreview(.full, plan: .pro)
}

#Preview("Card Settings · single card") {
    NavigationStack {
        CardSettingsView(cardID: PreviewStore.workCardID)
    }
    .metlyPreview(.empty)
}

#Preview("Card Settings · publishing (offline)") {
    PreviewPrepared(prepare: { PreviewStore.unpublish(PreviewStore.workCardID, in: $0) }) {
        NavigationStack {
            CardSettingsView(cardID: PreviewStore.workCardID)
        }
    }
    .metlyPreview(.full, online: false)
}

/// Beyond the Free limit after a downgrade: name, design and duplicate are locked.
#Preview("Card Settings · read-only card") {
    PreviewPrepared(prepare: { $0.record(Card.self, id: PreviewStore.personalCardID)?.isReadOnly = true }) {
        NavigationStack {
            CardSettingsView(cardID: PreviewStore.personalCardID)
        }
    }
    .metlyPreview(.full)
}

#Preview("Card Settings · deleted card") {
    NavigationStack {
        CardSettingsView(cardID: UUID())
    }
    .metlyPreview(.full)
}
#endif
