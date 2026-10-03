import MetlyCore
import MetlyData
import MetlySharedUI
import SwiftData
import SwiftUI

/// CARD_SETTINGS content: name, default, link, Home order, design/export/duplicate, delete.
struct CardSettingsForm: View {
    let card: Card
    /// Every live card, in Home order.
    let cards: [Card]
    let profile: Profile?

    @Environment(AppRouter.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var cardActions = CardActionCoordinator()
    @State private var isShowingDuplicateLimit = false
    @FocusState private var isNameFocused: Bool

    init(card: Card, cards: [Card], profile: Profile?) {
        self.card = card
        self.cards = cards
        self.profile = profile
        _name = State(initialValue: card.name)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Name") {
                    TextField("Card Name", text: $name)
                        .multilineTextAlignment(.trailing)
                        .textInputAutocapitalization(.words)
                        .submitLabel(.done)
                        .focused($isNameFocused)
                        .onSubmit(commitName)
                }
                Toggle("Default Card", isOn: isDefault)
            } header: {
                Text("Card")
            } footer: {
                Text("Used for Connect, events and widgets.")
            }

            CardLinkSection(card: card, isPaused: profile?.linksPaused ?? false)

            if cards.count > 1 {
                CardOrderSection(currentID: card.id, cards: cards, profile: profile, onReorder: reorder)
            }

            Section {
                Button("Edit Design", systemImage: "paintbrush", action: editDesign)
                    .disabled(card.isReadOnly)
                Button("Export…", systemImage: "square.and.arrow.down", action: export)
                Button("Duplicate Card", systemImage: "plus.square.on.square", action: duplicate)
            } footer: {
                if card.isReadOnly {
                    Text("This card is read-only on the Free plan.")
                }
            }

            Section {
                Button("Delete Card", systemImage: "trash", role: .destructive, action: delete)
            }
        }
        .navigationTitle("\(card.name) Card")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if cards.count > 1 {
                ToolbarItem(placement: .topBarTrailing) {
                    EditButton()
                }
            }
        }
        .cardActionAlerts(cardActions)
        .alert("Card Limit Reached", isPresented: $isShowingDuplicateLimit) {
            Button("Not Now", role: .cancel) {}
            Button("See Pro", action: showPaywall)
        } message: {
            Text("The Free plan includes 2 cards. Upgrade to \(Brand.proName) to duplicate this one.")
        }
        .onChange(of: isNameFocused) { _, focused in
            if !focused { commitName() }
        }
        .onChange(of: card.name) { _, newName in
            // A rename that arrived from sync.
            if !isNameFocused { name = newName }
        }
        .onDisappear(perform: commitName)
    }

    // MARK: Default

    private var isDefault: Binding<Bool> {
        Binding {
            CardLibrary.isDefault(card, among: cards, profile: profile)
        } set: { isOn in
            setDefault(isOn)
        }
    }

    private func setDefault(_ isOn: Bool) {
        guard let profile else { return }
        if isOn {
            CardLibrary.setDefault(card, profile: profile)
            services.sync.requestSync()
            router.showToast("\(card.name) is your default", systemImage: "checkmark.circle")
        } else if CardLibrary.isDefault(card, among: cards, profile: profile) {
            // At least one card is always the default.
            router.showToast("Pick another card as default", systemImage: "info.circle")
        }
    }

    // MARK: Actions

    private func commitName() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            name = card.name
            return
        }
        guard trimmed != card.name, !card.isDeleted else { return }
        card.name = trimmed
        card.markChanged()
        services.sync.requestSync()
    }

    private func reorder(_ order: [UUID]) {
        CardLibrary.applyOrder(order, to: cards)
        try? modelContext.save()
        services.sync.requestSync()
    }

    private func editDesign() {
        router.present(.cardEditor(cardID: card.id))
    }

    private func export() {
        router.present(.cardExport(cardID: card.id, tab: .image))
    }

    private func duplicate() {
        guard CardManagement.canCreateCard(existingCount: cards.count, limits: services.entitlements.limits) else {
            isShowingDuplicateLimit = true
            return
        }
        CardLibrary.duplicate(card, in: modelContext)
        try? modelContext.save()
        services.sync.requestSync()
        router.showToast("Card Duplicated", systemImage: "plus.square.on.square")
    }

    private func delete() {
        cardActions.perform(.delete, on: card, context: modelContext, router: router, services: services)
    }

    private func showPaywall() {
        router.present(.paywall(trigger: .cardLimit))
    }
}
