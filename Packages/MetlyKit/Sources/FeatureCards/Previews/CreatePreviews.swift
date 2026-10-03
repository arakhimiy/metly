#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// CARD_CREATE states (SPEC Appendix A #18, #20): method, gallery, style, details, done, limit, setup.

#Preview("Create · method (Pro)") {
    CardCreateView(origin: .home)
        .metlyPreview(.full, plan: .pro)
}

#Preview("Create · first card after setup (no Cancel)") {
    PreviewPrepared(prepare: PreviewStore.removeAllCards) {
        CardCreateView(origin: .setup)
    }
    .metlyPreview(.empty)
}

#Preview("Create · Free limit alert") {
    CardCreateView(origin: .home)
        .metlyPreview(.full, plan: .free)
}

#Preview("Create · template gallery (Free, Editorial locked)") {
    CardCreateScreen(origin: .home, initialPath: [.gallery])
        .metlyPreview(.empty, plan: .free)
}

#Preview("Create · template gallery (Pro)") {
    CardCreateScreen(origin: .home, initialPath: [.gallery])
        .metlyPreview(.empty, plan: .pro)
}

#Preview("Create · style (Free, Ocean/Ember locked)") {
    CardCreateScreen(origin: .home, initialPath: [.gallery, .style])
        .metlyPreview(.empty, plan: .free)
}

#Preview("Create · details") {
    CardCreateScreen(origin: .home, initialPath: [.gallery, .style, .details])
        .metlyPreview(.empty, plan: .free)
}

#Preview("Create · details · accessibility text") {
    CardCreateScreen(origin: .home, initialPath: [.details])
        .metlyPreview(.empty, plan: .free)
        .dynamicTypeSize(.accessibility2)
}

#Preview("Create · done (live)") {
    PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
        CreateSuccessView(card: card, profile: profile, createdOffline: false, onShare: {}, onDone: {})
    }
    .metlyPreview(.empty)
}

#Preview("Create · done (publishing)") {
    PreviewPrepared(prepare: { PreviewStore.unpublish(PreviewStore.workCardID, in: $0) }) {
        PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
            CreateSuccessView(card: card, profile: profile, createdOffline: false, onShare: {}, onDone: {})
        }
    }
    .metlyPreview(.empty)
}

#Preview("Create · publish failed (offline)") {
    PreviewPrepared(prepare: { PreviewStore.unpublish(PreviewStore.workCardID, in: $0) }) {
        PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
            CreateSuccessView(card: card, profile: profile, createdOffline: true, onShare: {}, onDone: {})
        }
    }
    .metlyPreview(.empty, online: false)
}
#endif
