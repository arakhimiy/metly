import MetlyCardKit
import MetlyCore
import SwiftUI
import WidgetKit

/// Nominal iPhone widget sizes used for the gallery's live previews.
enum WidgetPreviewSize {
    static let small = CGSize(width: 158, height: 158)
    static let medium = CGSize(width: 338, height: 158)
    static let rectangular = CGSize(width: 160, height: 72)
    static let circular = CGSize(width: 72, height: 72)
    static let cornerRadius: CGFloat = 22
    static let contentMargin: CGFloat = 16
}

/// A Home Screen widget preview: the real widget view with its background, content margins and corner
/// radius, outside WidgetKit. Text is capped at Large — it's a picture of a widget; the row below it
/// carries the readable description.
struct HomeWidgetPreview<Content: View, Background: ShapeStyle>: View {
    let size: CGSize
    let background: Background
    var contentMargin: CGFloat = WidgetPreviewSize.contentMargin
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(contentMargin)
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .background(background)
            .clipShape(.rect(cornerRadius: WidgetPreviewSize.cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
            .frame(maxWidth: size.width)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .allowsHitTesting(false)
    }
}

/// The "wallpaper" behind previews: the default card's palette (SPEC §2.5.16).
struct WidgetWallpaper<Content: View>: View {
    let design: CardDesign
    var dimmed = false
    @ViewBuilder let content: Content

    var body: some View {
        let colors = design.colors
        content
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .background {
                LinearGradient(colors: [colors.accent.color, colors.gradientEnd.color, colors.background.color],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay(Color.black.opacity(dimmed ? 0.45 : 0.08))
            }
            .clipShape(.rect(cornerRadius: 16, style: .continuous))
    }
}

/// One gallery row: preview on the wallpaper, then title + description.
struct WidgetShowcaseRow<Preview: View>: View {
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let design: CardDesign
    var dimmedWallpaper = false
    let accessibilityPreview: Text
    @ViewBuilder let preview: Preview

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WidgetWallpaper(design: design, dimmed: dimmedWallpaper) { preview }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityPreview)
                .accessibilityAddTraits(.isImage)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 6)
    }
}
