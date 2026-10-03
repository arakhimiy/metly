import MetlyCardKit
import MetlyCore
import SwiftUI

/// Editor "Color": palette swatches, Light / Dark appearance, gradient background.
struct EditorColorSection: View {
    @Binding var design: CardDesign
    let allowsPro: Bool
    let onSelectPalette: (CardPalette) -> Void

    var body: some View {
        Section {
            PaletteGrid(design: design, allowsPro: allowsPro, onSelect: onSelectPalette)
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

        Section {
            Toggle("Gradient Background", isOn: gradient)
                .disabled(design.template == .gradient)
        } footer: {
            if design.template == .gradient {
                Text("The Gradient template is always gradient.")
            }
        }
    }

    private var gradient: Binding<Bool> {
        Binding {
            design.usesGradientFill
        } set: { isOn in
            if case .updated(let updated) = CardDesignRules.settingGradient(isOn, in: design) {
                design = updated
            }
        }
    }
}
