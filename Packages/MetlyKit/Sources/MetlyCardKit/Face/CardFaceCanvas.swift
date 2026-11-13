import MetlyCore
import SwiftUI

/// Renders one card face at an explicit width. `CardFaceView` wraps it with a GeometryReader;
/// exporters use it directly (square corners + bleed for print).
///
/// With `bleed > 0` the fill and edge-touching panels extend `bleed` points past the trim on every
/// side while the content stays laid out on the trim box — the view is `width + 2·bleed` wide.
struct CardFaceCanvas: View {
    enum Corners { case rounded, square }

    let design: CardDesign
    let content: CardFaceContent
    let width: CGFloat
    var bleed: CGFloat = 0
    var corners: Corners = .rounded

    var body: some View {
        let style = CardFaceStyle(design: design, width: width)
        let model = CardFaceModel(design: design, content: content)
        let size = CGSize(width: width + 2 * bleed, height: style.height + 2 * bleed)

        ZStack(alignment: .topLeading) {
            Rectangle().fill(style.colors.fill(gradient: style.gradientFill, size: size))
            CardEdgeDecor(design: design, style: style, bleed: bleed)
            if design.template.hasPaperGrain, width >= CardPaperGrain.minimumWidth {
                CardPaperGrain(isDark: style.colors.background.isDark, dotSize: style.hairline * 1.2)
            }
            CardTemplateContent(design: design, model: model, style: style)
                .frame(width: width, height: style.height)
                .padding(bleed)
        }
        .frame(width: size.width, height: size.height)
        .foregroundStyle(style.fg)
        .environment(\.colorScheme, design.appearance == .dark ? .dark : .light)
        .clipShape(.rect(cornerRadius: corners == .rounded ? width * CardFaceShape.cornerFraction : 0,
                         style: .continuous))
    }
}

/// Template switch.
struct CardTemplateContent: View {
    let design: CardDesign
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        switch design.template {
        case .minimal: MinimalTemplate(model: model, style: style)
        case .professional: ProfessionalTemplate(model: model, style: style)
        case .modern: ModernTemplate(model: model, style: style, foil: .holographic(for: design.palette))
        case .bold: BoldTemplate(model: model, style: style)
        case .gradient: GradientTemplate(model: model, style: style, ink: CardAurora.foreground(design))
        case .split: SplitTemplate(model: model, style: style)
        case .terminal: TerminalTemplate(model: model, style: style)
        case .stack: StackTemplate(model: model, style: style)
        case .editorial: EditorialTemplate(model: model, style: style, foil: .metal(for: design.palette, appearance: design.appearance))
        }
    }
}

/// Fills and panels that touch the card edge (Aurora gradient, Duotone panel); they run into the bleed.
struct CardEdgeDecor: View {
    let design: CardDesign
    let style: CardFaceStyle
    let bleed: CGFloat

    var body: some View {
        let fullHeight = style.height + 2 * bleed
        switch design.template {
        case .gradient:
            CardAuroraFill(design: design, width: style.width, lineWidth: style.hairline)
                .frame(width: style.width + 2 * bleed, height: fullHeight)
        case .split:
            Rectangle().fill(style.accent).frame(width: bleed + style.u(36), height: fullHeight)
        default:
            EmptyView()
        }
    }
}

extension CardTemplate {
    /// Templates printed on a textured stock.
    var hasPaperGrain: Bool { [.minimal, .modern, .editorial].contains(self) }
}
