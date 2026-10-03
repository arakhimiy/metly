import MetlyCardKit
import MetlyCore
import SwiftUI

/// Editor "Type": typeface, alignment and density (SPEC §2.5.24).
struct EditorTypeSection: View {
    @Binding var design: CardDesign

    var body: some View {
        Section {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 10)], spacing: 10) {
                ForEach(CardFont.allCases) { font in
                    Button {
                        design.font = font
                    } label: {
                        TypefaceTile(font: font, isSelected: design.effectiveFont == font)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
            .disabled(!design.templateAllowsFontChoice)
            .sensoryFeedback(.selection, trigger: design.font)
        } header: {
            Text("Typeface")
        } footer: {
            if !design.templateAllowsFontChoice {
                Text("This template sets its own typeface.")
            }
        }

        Section {
            Picker("Alignment", selection: $design.alignment) {
                Text("Leading").tag(CardAlignment.leading)
                Text("Center").tag(CardAlignment.center)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!design.templateAllowsAlignment)
        } header: {
            Text("Alignment")
        } footer: {
            if !design.templateAllowsAlignment {
                Text("Alignment applies to the Minimal, Bold and Gradient templates.")
            }
        }

        Section {
            Picker("Density", selection: $design.density) {
                ForEach(CardDensity.allCases) { density in
                    Text(density.title).tag(density)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        } header: {
            Text("Density")
        } footer: {
            Text("Shows up to \(design.density.maxContacts) contact lines.")
        }
    }
}
