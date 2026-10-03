import MetlyCore
import SwiftUI

/// Interactive picker preview for the gallery helpers (editor grid, create gallery, palette row).
private struct GalleryPreview: View {
    let columns: Int
    @State private var template: CardTemplate = .modern
    @State private var palette: CardPalette = .ink
    @State private var appearance: CardAppearance = .dark

    private var design: CardDesign { CardDesign(template: template, palette: palette, appearance: appearance) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                CardFaceView(design: design, content: .sample).cardFaceElevation()
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 16) {
                    ForEach(CardTemplate.allCases) { item in
                        Button {
                            template = item
                        } label: {
                            CardTemplateThumbnail(template: item, design: design, isSelected: item == template,
                                                  isLocked: item.isPro)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Picker("Card Appearance", selection: $appearance) {
                    Text("Light").tag(CardAppearance.light)
                    Text("Dark").tag(CardAppearance.dark)
                }
                .pickerStyle(.segmented)
                HStack {
                    ForEach(CardPalette.allCases) { item in
                        Button {
                            palette = item
                        } label: {
                            CardPaletteSwatch(palette: item, appearance: appearance, isSelected: item == palette,
                                              isLocked: item.isPro)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
        }
        .sensoryFeedback(.selection, trigger: design)
    }
}

#Preview("Gallery · editor 3-col") { GalleryPreview(columns: 3) }
#Preview("Gallery · create 2-col") { GalleryPreview(columns: 2) }
#Preview("Gallery · dark mode") { GalleryPreview(columns: 3).preferredColorScheme(.dark) }

#Preview("QR code") {
    VStack(spacing: 24) {
        QRCodeView(payload: Brand.cardURL(slug: "kamola-7f3k").absoluteString)
            .frame(width: 260)
        QRCodeView(payload: VCardBuilder.make(content: .sample, url: Brand.cardURL(slug: "kamola-7f3k")))
            .frame(width: 260)
        QRCodeView(payload: String(repeating: "x", count: 4000))   // too long → placeholder
            .frame(width: 80)
    }
    .padding()
    .background(Color(white: 0.9))
}
