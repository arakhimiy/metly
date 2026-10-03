import MetlyCore
import SwiftUI

/// FROZEN PUBLIC API — renders a business card face (85 : 55) for any template / palette / appearance.
///
/// Implements SPEC Appendix B: 9 templates, 6 palettes × light/dark, fonts, density, alignment,
/// gradient background, photo/logo with initials/monogram fallbacks and the QR plate. Every size is
/// proportional to the card width, so the same view works from a 56 pt thumbnail to full width and
/// inside `ImageRenderer`. The face takes the largest 85:55 rectangle that fits the proposal.
///
/// `content.fields` should already be filtered for the audience (`CardAudience`); the renderer also
/// enforces the card rules itself: design-visible fields only, never Private, fixed order, density limit.
public struct CardFaceView: View {
    public let design: CardDesign
    public let content: CardFaceContent

    public init(design: CardDesign, content: CardFaceContent) {
        self.design = design
        self.content = content
    }

    /// Business-card aspect ratio (85 × 55 mm).
    public nonisolated static let aspectRatio: CGFloat = 85.0 / 55.0

    public var body: some View {
        // GeometryReader is required here: every font and inset is a fraction of the rendered width.
        GeometryReader { proxy in
            CardFaceCanvas(design: design, content: content, width: proxy.size.width)
        }
        .aspectRatio(Self.aspectRatio, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: CardFaceModel(design: design, content: content).accessibilityDescription))
    }
}

public extension CardFaceView {
    /// Sample person for template/palette pickers and previews.
    nonisolated static var sample: CardFaceContent { .sample }
}
