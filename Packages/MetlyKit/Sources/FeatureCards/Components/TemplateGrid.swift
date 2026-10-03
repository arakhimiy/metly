import MetlyCardKit
import MetlyCore
import SwiftUI

/// The 9 templates rendered with the user's own details (editor: 3 columns, create gallery: 2).
/// Pro templates show the PRO lock on the Free plan; what happens on tap is up to the caller.
struct TemplateGrid: View {
    let columns: Int
    let design: CardDesign
    let content: CardFaceContent
    let allowsPro: Bool
    let onSelect: (CardTemplate) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        LazyVGrid(columns: gridColumns, spacing: 16) {
            ForEach(CardTemplate.allCases) { template in
                Button {
                    onSelect(template)
                } label: {
                    CardTemplateThumbnail(template: template, design: design, content: content,
                                          isSelected: design.template == template,
                                          isLocked: CardDesignRules.isLocked(template, allowsPro: allowsPro))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isButton)
            }
        }
        .sensoryFeedback(.selection, trigger: design.template)
    }

    /// One column fewer at accessibility text sizes so titles stay readable.
    private var gridColumns: [GridItem] {
        let count = dynamicTypeSize.isAccessibilitySize ? max(columns - 1, 1) : columns
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }
}
