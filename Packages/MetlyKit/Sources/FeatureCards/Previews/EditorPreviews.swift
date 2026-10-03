#if DEBUG
import MetlyCore
import MetlyData
import SwiftUI

// CARD_EDITOR states (SPEC Appendix A #49): every tab, Pro locks on Free, forced font/gradient.

#Preview("Editor · Template (Free, Editorial locked)") {
    CardEditorView(cardID: PreviewStore.workCardID)
        .metlyPreview(.full, plan: .free)
}

#Preview("Editor · Template (Pro)") {
    CardEditorView(cardID: PreviewStore.workCardID)
        .metlyPreview(.full, plan: .pro)
}

#Preview("Editor · Color (Free, Ocean/Ember locked)") {
    PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
        CardEditorForm(card: card, profile: profile, initialTab: .color)
    }
    .metlyPreview(.full, plan: .free)
}

#Preview("Editor · Color · Gradient template") {
    PreviewPrepared(prepare: {
        PreviewStore.useDesign(CardDesign(template: .gradient, palette: .sand, background: .gradient),
                               for: PreviewStore.workCardID, in: $0)
    }) {
        PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
            CardEditorForm(card: card, profile: profile, initialTab: .color)
        }
    }
    .metlyPreview(.full, plan: .pro)
}

#Preview("Editor · Type") {
    PreviewPrepared(prepare: {
        PreviewStore.useDesign(CardDesign(template: .minimal, palette: .graphite), for: PreviewStore.workCardID, in: $0)
    }) {
        PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
            CardEditorForm(card: card, profile: profile, initialTab: .type)
        }
    }
    .metlyPreview(.full)
}

#Preview("Editor · Type · Terminal sets typeface") {
    PreviewPrepared(prepare: {
        PreviewStore.useDesign(CardDesign(template: .terminal, palette: .graphite), for: PreviewStore.workCardID, in: $0)
    }) {
        PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
            CardEditorForm(card: card, profile: profile, initialTab: .type)
        }
    }
    .metlyPreview(.full)
}

#Preview("Editor · Fields (private phone)") {
    PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
        CardEditorForm(card: card, profile: profile, initialTab: .fields)
    }
    .metlyPreview(.full)
}

#Preview("Editor · Media") {
    PreviewPrepared(prepare: {
        PreviewStore.addPhoto(in: $0)
        PreviewStore.useDesign(CardDesign(template: .modern, palette: .ink), for: PreviewStore.workCardID, in: $0)
    }) {
        PreviewCard(cardID: PreviewStore.workCardID) { card, profile in
            CardEditorForm(card: card, profile: profile, initialTab: .media)
        }
    }
    .metlyPreview(.full)
}

#Preview("Editor · Dark, accessibility text") {
    PreviewCard(cardID: PreviewStore.personalCardID) { card, profile in
        CardEditorForm(card: card, profile: profile, initialTab: .fields)
    }
    .metlyPreview(.full)
    .preferredColorScheme(.dark)
    .dynamicTypeSize(.accessibility1)
}
#endif
