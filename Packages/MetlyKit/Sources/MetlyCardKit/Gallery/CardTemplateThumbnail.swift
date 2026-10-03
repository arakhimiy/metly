import MetlyCore
import SwiftUI

/// Template tile for the editor grid (3-col) and create gallery (2-col): live card preview,
/// selection ring + checkmark, PRO lock badge, optional title.
///
/// Not a button — wrap it in one (`Button { … } label: { CardTemplateThumbnail(…) }.buttonStyle(.plain)`).
public struct CardTemplateThumbnail: View {
    let template: CardTemplate
    let design: CardDesign
    let content: CardFaceContent
    let isSelected: Bool
    let isLocked: Bool
    let showsTitle: Bool

    /// - Parameters:
    ///   - design: base design (palette, appearance, fields…); its template is replaced by `template`.
    ///   - content: values to render — the user's own, or `.sample`.
    ///   - isLocked: shows the PRO lock badge (e.g. Editorial on the Free plan).
    public init(template: CardTemplate, design: CardDesign = CardDesign(), content: CardFaceContent = .sample,
                isSelected: Bool = false, isLocked: Bool = false, showsTitle: Bool = true) {
        self.template = template
        self.design = design
        self.content = content
        self.isSelected = isSelected
        self.isLocked = isLocked
        self.showsTitle = showsTitle
    }

    private static let ringGap: CGFloat = 3
    private static let ringWidth: CGFloat = 2.5

    public var body: some View {
        VStack(spacing: 6) {
            CardFaceView(design: resolvedDesign, content: content)
                .padding(Self.ringGap + Self.ringWidth)
                .overlay {
                    CardFaceShape(outset: Self.ringGap + Self.ringWidth)
                        .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: Self.ringWidth)
                }
                .overlay(alignment: .topTrailing) {
                    CardThumbnailBadge(isSelected: isSelected, isLocked: isLocked)
                }
            if showsTitle {
                Text(template.title)
                    .font(.footnote.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(template.title) template"))
        .accessibilityValue(isLocked ? Text("Requires \(Brand.proName)") : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var resolvedDesign: CardDesign {
        var copy = design
        copy.template = template
        return copy
    }
}

/// Checkmark (selected) or PRO lock badge in the top-trailing corner of a thumbnail.
struct CardThumbnailBadge: View {
    let isSelected: Bool
    let isLocked: Bool

    var body: some View {
        if isLocked {
            CardProLockBadge()
                .padding(8)
        } else if isSelected {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, Color.accentColor)
                .font(.title3)
                .background(Circle().fill(.white).padding(3))
                .padding(4)
        }
    }
}

/// Lock + "PRO" capsule for gated templates.
public struct CardProLockBadge: View {
    public init() {}

    public var body: some View {
        Label("PRO", systemImage: "lock.fill")
            .labelStyle(CardBadgeLabelStyle())
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.72), in: .capsule)
            .accessibilityLabel(Text("Requires \(Brand.proName)"))
    }
}

private struct CardBadgeLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 3) {
            configuration.icon.imageScale(.small)
            configuration.title
        }
    }
}
