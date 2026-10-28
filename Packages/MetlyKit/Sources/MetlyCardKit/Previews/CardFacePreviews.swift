import MetlyCore
import SwiftUI

// Appendix B checklist: every template × palette × appearance, plus density / alignment / font /
// background / media / content-length variants and thumbnail sizes.

#Preview("All templates × palettes") {
    ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(CardTemplate.allCases) { template in
                Section {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                        ForEach(CardPalette.allCases) { palette in
                            ForEach(CardAppearance.allCases, id: \.self) { appearance in
                                CardFaceView(design: CardDesign(template: template, palette: palette, appearance: appearance),
                                             content: .sample)
                                    .cardFaceElevation()
                            }
                        }
                    }
                } header: {
                    Text(template.title).font(.headline)
                }
            }
        }
        .padding()
    }
}

#Preview("Density") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(CardDensity.allCases) { density in
                ForEach([CardTemplate.minimal, .split, .stack]) { template in
                    CardFaceView(design: CardDesign(template: template, palette: .ink, appearance: .dark, density: density,
                                                    visibleFields: Set(ContactFieldKind.allCases)),
                                 content: .sample)
                }
            }
        }
        .padding()
    }
}

#Preview("Alignment · centre") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(CardTemplate.allCases) { template in
                CardFaceView(design: CardDesign(template: template, palette: .ocean, appearance: .light, alignment: .center),
                             content: .sample)
                    .cardFaceElevation()
            }
        }
        .padding()
    }
}

#Preview("Fonts & gradient background") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(CardFont.allCases) { font in
                CardFaceView(design: CardDesign(template: .modern, palette: .ember, appearance: .light, font: font,
                                                background: .gradient),
                             content: .sample)
            }
            CardFaceView(design: CardDesign(template: .terminal, palette: .graphite, font: .serif), content: .sample)
            CardFaceView(design: CardDesign(template: .editorial, palette: .sand, appearance: .light, font: .mono),
                         content: .sample)
        }
        .padding()
    }
}

#Preview("Long values & fallbacks") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach(CardTemplate.allCases) { template in
                CardFaceView(design: CardDesign(template: template, palette: .graphite, appearance: .dark, density: .detailed,
                                                visibleFields: Set(ContactFieldKind.allCases)),
                             content: .sampleLong)
            }
            ForEach([CardTemplate.professional, .modern, .split, .stack]) { template in
                CardFaceView(design: CardDesign(template: template, palette: .snow, appearance: .light, showQR: false),
                             content: .sampleMinimal)
                    .cardFaceElevation()
            }
        }
        .padding()
    }
}

/// Regression: long names / titles next to the bottom-right QR plate (Professional name, Gradient title).
#Preview("Long text beside the QR") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach([CardDensity.minimal, .balanced], id: \.self) { density in
                CardFaceView(design: CardDesign(template: .professional, palette: .ink, appearance: .dark,
                                                density: density, visibleFields: Set(ContactFieldKind.allCases)),
                             content: .sampleLong)
                ForEach(CardAlignment.allCases, id: \.self) { alignment in
                    CardFaceView(design: CardDesign(template: .gradient, palette: .ink, appearance: .dark,
                                                    alignment: alignment, density: density,
                                                    visibleFields: Set(ContactFieldKind.allCases)),
                                 content: .sampleLong)
                }
            }
        }
        .padding()
    }
}

/// Several labelled phones: Detailed fits all three numbers (+ two more lines); Balanced keeps one line
/// per kind, so the extra numbers stay off; a card showing only phones shows all of them.
#Preview("Several phones") {
    let phonesAndEmail: Set<ContactFieldKind> = [.phone, .email]
    ScrollView {
        VStack(spacing: 16) {
            ForEach(CardTemplate.allCases) { template in
                Text(template.title).font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                CardFaceView(design: CardDesign(template: template, palette: .ink, appearance: .dark, density: .detailed,
                                                visibleFields: phonesAndEmail),
                             content: .sampleSeveralPhones)
                CardFaceView(design: CardDesign(template: template, palette: .snow, appearance: .light, density: .balanced,
                                                visibleFields: [.phone]),
                             content: .sampleSeveralPhones)
                    .cardFaceElevation()
            }
        }
        .padding()
    }
}

#Preview("Several phones · centre, long") {
    ScrollView {
        VStack(spacing: 16) {
            ForEach([CardTemplate.minimal, .bold, .gradient]) { template in
                CardFaceView(design: CardDesign(template: template, palette: .ocean, appearance: .light, alignment: .center,
                                                density: .detailed, visibleFields: [.phone, .website]),
                             content: .sampleSeveralPhones)
                    .cardFaceElevation()
            }
            CardFaceView(design: CardDesign(template: .split, palette: .graphite, density: .detailed,
                                            visibleFields: Set(ContactFieldKind.allCases)),
                         content: .sampleSeveralPhones)
            CardFaceView(design: CardDesign(template: .stack, palette: .sand, appearance: .light, density: .detailed,
                                            visibleFields: [.phone]),
                         content: .sampleSeveralPhones)
                .frame(width: 96)
        }
        .padding()
    }
}

#Preview("Thumbnail sizes") {
    VStack(alignment: .leading, spacing: 16) {
        HStack {
            ForEach(CardTemplate.allCases.prefix(5)) { template in
                CardFaceView(design: CardDesign(template: template), content: .sample).frame(width: 56)
            }
        }
        HStack {
            ForEach(CardTemplate.allCases.prefix(3)) { template in
                CardFaceView(design: CardDesign(template: template, palette: .sand, appearance: .light), content: .sample)
                    .frame(width: 96)
                    .cardFaceElevation()
            }
        }
        CardFaceView(design: CardDesign(template: .split, palette: .ocean), content: .sample)
            .cardFaceElevation()
    }
    .padding()
}
