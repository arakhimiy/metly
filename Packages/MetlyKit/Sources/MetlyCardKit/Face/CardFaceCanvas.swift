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
            CardEdgeDecor(template: design.template, style: style, bleed: bleed)
            CardTemplateContent(template: design.template, model: model, style: style)
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
    let template: CardTemplate
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        switch template {
        case .minimal: MinimalTemplate(model: model, style: style)
        case .professional: ProfessionalTemplate(model: model, style: style)
        case .modern: ModernTemplate(model: model, style: style)
        case .bold: BoldTemplate(model: model, style: style)
        case .gradient: GradientTemplate(model: model, style: style)
        case .split: SplitTemplate(model: model, style: style)
        case .terminal: TerminalTemplate(model: model, style: style)
        case .stack: StackTemplate(model: model, style: style)
        case .editorial: EditorialTemplate(model: model, style: style)
        }
    }
}

/// Accent areas that touch the card edge (Modern stripe, Split panel); they run into the bleed.
struct CardEdgeDecor: View {
    let template: CardTemplate
    let style: CardFaceStyle
    let bleed: CGFloat

    var body: some View {
        let fullHeight = style.height + 2 * bleed
        switch template {
        case .modern:
            Rectangle().fill(style.accent).frame(width: bleed + style.u(2.2), height: fullHeight)
        case .split:
            Rectangle().fill(style.accent).frame(width: bleed + style.u(36), height: fullHeight)
        default:
            EmptyView()
        }
    }
}
