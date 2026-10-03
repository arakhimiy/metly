import MetlyCardKit
import MetlyCore
import SwiftUI

/// A full-width card face inside a Form, without the row background.
struct CardPreviewRow: View {
    let design: CardDesign
    let content: CardFaceContent
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CardFaceView(design: design, content: content)
            .cardFaceElevation()
            // Leave room for text controls at accessibility sizes.
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 260 : 420)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
    }
}
