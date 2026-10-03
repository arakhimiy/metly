import MetlyCardKit
import MetlyCore
import SwiftUI

/// Live card preview pinned above the editor form, with the section picker under it.
struct EditorPreviewHeader: View {
    let design: CardDesign
    let content: CardFaceContent
    @Binding var tab: EditorTab
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 14) {
            CardFaceView(design: design, content: content)
                .cardFaceElevation()
                .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 200 : 380)
                .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: design)

            Picker("Section", selection: $tab) {
                ForEach(EditorTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}
