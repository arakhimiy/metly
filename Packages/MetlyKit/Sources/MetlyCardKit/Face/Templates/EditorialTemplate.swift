import SwiftUI

/// Editorial (Pro) — New York serif, metal foil (silver / gold / rose by palette) on a large cropped logo
/// or initial and on the hairline; contacts set like a colophon, the company in spaced capitals. [GEARWORKS]
struct EditorialTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle
    let foil: CardFoil

    var body: some View {
        ZStack(alignment: .topLeading) {
            art
                .frame(width: style.u(44), height: style.u(44))
                .offset(x: -style.u(8))
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                CardText(text: model.fullName, style: style, size: 5.8, weight: .medium, tracking: 0.01, lineLimit: 2,
                         minimumScale: 0.6)
                if !model.jobTitle.isEmpty {
                    Text(verbatim: model.jobTitle)
                        .font(style.font(3.1).italic())
                        .foregroundStyle(style.muted)
                        .lineLimit(2)
                        .padding(.top, style.u(0.8))
                }
                Rectangle().fill(foil.gradient).frame(height: max(style.u(0.3), style.hairline))
                    .padding(.vertical, style.u(3))
                CardPlainContacts(contacts: model.contacts, style: style, fontSize: 2.8, spacing: 0.7)
                Spacer(minLength: style.u(2))
                if !model.company.isEmpty {
                    CardText(text: model.company, style: style, size: 2.9, tracking: 0.24, uppercase: true)
                        .padding(.trailing, model.showsQR ? style.u(15) : 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, style.u(44))
            .padding([.top, .trailing, .bottom], style.u(8))
        }
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 12, cornerRadius: 1.2).padding(style.u(6.5))
            }
        }
    }

    /// The logo stamped in foil (a transparent PNG), else the initial in foil.
    @ViewBuilder
    private var art: some View {
        if let logo = model.logoData, CardImageDecoder.hasTransparency(logo) {
            CardLogoMark(data: logo, style: .mono, ink: foil.gradient, width: style.u(40), height: style.u(40))
        } else if let logo = model.logoData {
            CardLogoMark(data: logo, style: .original, ink: style.fg, width: style.u(22), height: style.u(22))
                .offset(x: style.u(8))
        } else {
            Text(verbatim: model.monogram)
                .font(.system(size: max(style.u(44), 1), weight: .regular, design: .serif))
                .foregroundStyle(foil.gradient)
                .lineLimit(1)
                .accessibilityHidden(true)
        }
    }
}
