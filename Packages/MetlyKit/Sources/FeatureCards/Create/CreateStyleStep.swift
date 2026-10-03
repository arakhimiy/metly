import MetlyCore
import MetlyDesign
import SwiftUI

/// Step 3 — "Style": palette (Ocean / Ember are Pro) and Light / Dark, with a live preview.
struct CreateStyleStep: View {
    @Binding var design: CardDesign
    let content: CardFaceContent
    let allowsPro: Bool
    let onRequirePro: (PaywallTrigger) -> Void
    let onContinue: () -> Void

    var body: some View {
        Form {
            Section {
                CardPreviewRow(design: design, content: content)
            }

            Section {
                PaletteGrid(design: design, allowsPro: allowsPro, onSelect: select)
            } header: {
                Text("Palette")
            } footer: {
                PaletteFooter(design: design)
            }

            Section("Card Appearance") {
                Picker("Card Appearance", selection: $design.appearance) {
                    Text("Light").tag(CardAppearance.light)
                    Text("Dark").tag(CardAppearance.dark)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
        .navigationTitle("Style")
        .navigationBarTitleDisplayMode(.inline)
        .createProgress(CreateStep.style.progress)
        .bottomActionBar {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
        }
    }

    private func select(_ palette: CardPalette) {
        switch CardDesignRules.selecting(palette, in: design, allowsPro: allowsPro) {
        case .updated(let updated): design = updated
        case .requiresPro(let trigger): onRequirePro(trigger)
        case .blocked: break
        }
    }
}
