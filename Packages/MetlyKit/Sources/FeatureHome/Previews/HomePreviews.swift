#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// SPEC Appendix A state 6 (HOME) and its variants: offline, event active/inactive, empty demo data,
// single card, draft card (state 20 publish failed), nothing due today. Long-press a card in Live
// Preview for CARD_PREVIEW_MENU (state 14).

#Preview("Home · full (active event)") {
    NavigationStack { HomeView() }
        .metlyPreview(.full)
}

#Preview("Home · empty account") {
    NavigationStack { HomeView() }
        .metlyPreview(.empty)
}

#Preview("Home · offline") {
    NavigationStack { HomeView() }
        .metlyPreview(.full, online: false)
}

#Preview("Home · no event") {
    NavigationStack {
        HomePreviewPrepared(prepare: HomePreviewData.endActiveEvent) {
            HomeView()
        }
    }
    .metlyPreview(.full)
}

#Preview("Home · 1 card") {
    NavigationStack {
        HomePreviewPrepared(prepare: HomePreviewData.keepOnlyWorkCard) {
            HomeView()
        }
    }
    .metlyPreview(.full)
}

#Preview("Home · draft card (publish failed)") {
    NavigationStack {
        HomePreviewPrepared(prepare: { context in
            HomePreviewData.keepOnlyWorkCard(in: context)
            HomePreviewData.makeWorkCardDraft(in: context)
        }) {
            HomeView()
        }
    }
    .metlyPreview(.full, online: false)
}

#Preview("Home · nothing due today") {
    NavigationStack {
        HomePreviewPrepared(prepare: HomePreviewData.nothingDueToday) {
            HomeView()
        }
    }
    .metlyPreview(.full)
}

#Preview("Home · Pro, dark, large text") {
    NavigationStack { HomeView() }
        .metlyPreview(.full, plan: .pro)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility2)
}
#endif
