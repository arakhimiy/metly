import MetlyCore
import MetlyDesign
import SwiftUI

/// Step 2 — "Templates": the 9 layouts with the user's own details, 2 per row.
/// Editorial is Pro: on Free it opens the paywall.
struct CreateGalleryStep: View {
    @Binding var design: CardDesign
    let content: CardFaceContent
    let allowsPro: Bool
    let onRequirePro: (PaywallTrigger) -> Void
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Pick a layout. Your details fill it in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                TemplateGrid(columns: 2, design: design, content: content, allowsPro: allowsPro, onSelect: select)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Templates")
        .navigationBarTitleDisplayMode(.inline)
        .createProgress(CreateStep.gallery.progress)
        .bottomActionBar {
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .prominentButtonStyle()
            .controlSize(.large)
        }
    }

    private func select(_ template: CardTemplate) {
        switch CardDesignRules.selecting(template, in: design, allowsPro: allowsPro) {
        case .updated(let updated): design = updated
        case .requiresPro(let trigger): onRequirePro(trigger)
        case .blocked: break
        }
    }
}
