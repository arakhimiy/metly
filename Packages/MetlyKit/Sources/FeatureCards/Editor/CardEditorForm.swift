import MetlyCardKit
import MetlyCore
import MetlyData
import SwiftUI

/// CARD_EDITOR body. Edits a `CardDraft` copy: Cancel discards it (after confirmation when dirty),
/// Done writes it once and the sync engine republishes the page and Wallet pass (SPEC §9 Q12).
struct CardEditorForm: View {
    let card: Card
    let profile: Profile?

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services

    @State private var original: CardDraft
    @State private var draft: CardDraft
    @State private var tab: EditorTab
    @State private var isConfirmingDiscard = false
    @State private var lockedTemplate: CardTemplate?

    init(card: Card, profile: Profile?, initialTab: EditorTab = .template) {
        self.card = card
        self.profile = profile
        let draft = CardDraft(card: card)
        _original = State(initialValue: draft)
        _draft = State(initialValue: draft)
        _tab = State(initialValue: initialTab)
    }

    var body: some View {
        NavigationStack {
            Form {
                if card.isReadOnly {
                    ReadOnlyCardNotice()
                }
                tabContent
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                EditorPreviewHeader(design: draft.design, content: previewContent, tab: $tab)
            }
            .navigationTitle("\(draft.trimmedName.isEmpty ? card.name : draft.trimmedName) Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert(lockedTemplateTitle, isPresented: isShowingProTemplateAlert, presenting: lockedTemplate) { _ in
                Button("Not Now", role: .cancel) {}
                Button("See Pro", action: showTemplatePaywall)
            } message: { _ in
                Text("Upgrade to \(Brand.proName) to use Editorial and every palette.")
            }
        }
    }

    // MARK: Sections

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .template:
            Section {
                TemplateGrid(columns: 3, design: draft.design, content: previewContent,
                             allowsPro: allowsPro, onSelect: select)
                    .padding(.vertical, 6)
            } footer: {
                Text("Your details fill every layout. You can switch any time.")
            }
        case .color:
            EditorColorSection(design: $draft.design, allowsPro: allowsPro, onSelectPalette: select)
        case .type:
            EditorTypeSection(design: $draft.design)
        case .fields:
            CardFieldsSection(fields: profile?.contactFields ?? ContactField.defaults, design: $draft.design,
                              footer: "Values come from your profile. Private fields never appear on a card. Connections fields show only in the app to people you’ve connected with.")
        case .media:
            EditorMediaSection(draft: $draft, profile: profile)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", action: cancel)
                .confirmationDialog("Discard Changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                    Button("Discard Changes", role: .destructive, action: router.dismiss)
                    Button("Keep Editing", role: .cancel) {}
                } message: {
                    Text("Your changes to this card won’t be saved.")
                }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Done", action: save)
                .disabled(card.isReadOnly)
        }
    }

    // MARK: State

    private var isDirty: Bool { draft != original }

    private var allowsPro: Bool { services.entitlements.limits.allowsProTemplates }

    /// In-app preview: Public + Connections fields, the draft's photo/logo.
    private var previewContent: CardFaceContent {
        CardContentFactory.content(profile: profile, design: draft.design, audience: .connections,
                                   qrPayload: card.url?.absoluteString ?? "", photo: draft.photo, logo: draft.logo)
    }

    private var lockedTemplateTitle: String {
        "\(lockedTemplate?.title ?? CardTemplate.editorial.title) Is a Pro Template"
    }

    private var isShowingProTemplateAlert: Binding<Bool> {
        Binding(get: { lockedTemplate != nil }, set: { if !$0 { lockedTemplate = nil } })
    }

    // MARK: Actions

    private func select(_ template: CardTemplate) {
        switch CardDesignRules.selecting(template, in: draft.design, allowsPro: allowsPro) {
        case .updated(let design): draft.design = design
        case .requiresPro: lockedTemplate = template
        case .blocked: break
        }
    }

    private func select(_ palette: CardPalette) {
        switch CardDesignRules.selecting(palette, in: draft.design, allowsPro: allowsPro) {
        case .updated(let design): draft.design = design
        case .requiresPro(let trigger): router.present(.paywall(trigger: trigger))
        case .blocked: break
        }
    }

    private func showTemplatePaywall() {
        router.present(.paywall(trigger: .proTemplate))
    }

    private func cancel() {
        if isDirty {
            isConfirmingDiscard = true
        } else {
            router.dismiss()
        }
    }

    private func save() {
        let commit = draft.apply(to: card, profile: profile)
        router.dismiss()
        guard commit.changedAnything else { return }
        services.sync.requestSync()
        let published = card.url != nil && services.network.isOnline
        router.showToast(published ? "\(card.name) Card Published" : "\(card.name) Card Saved",
                         systemImage: "checkmark.circle")
    }
}

/// Shown when a card became read-only after a Pro downgrade (beyond the Free card limit).
private struct ReadOnlyCardNotice: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        Section {
            Button("See \(Brand.proName)", systemImage: "crown") {
                router.present(.paywall(trigger: .cardLimit))
            }
        } header: {
            Text("Read-Only Card")
        } footer: {
            Text("The Free plan includes 2 cards, so this one can’t be edited. Upgrade to edit it again.")
        }
    }
}
