import SwiftUI

/// Monogram (`professional`) — the logo, or the initial, blind-debossed into the left of the card;
/// the name is the card's one accent. [black card, debossed monogram, cyan name]
struct ProfessionalTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        HStack(spacing: 0) {
            deboss
                .frame(width: style.u(44))
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: 0) {
                if model.showsQR {
                    CardQRPlate(payload: model.qrPayload, style: style, size: 12, cornerRadius: 1.2)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                Spacer(minLength: style.u(2))
                VStack(alignment: .leading, spacing: style.u(0.9)) {
                    CardText(text: model.fullName, style: style, size: 4.6, weight: .semibold, tracking: -0.01,
                             color: style.accent, lineLimit: 2, minimumScale: 0.6)
                    if !model.jobTitle.isEmpty {
                        CardText(text: model.jobTitle, style: style, size: 2.9, lineLimit: 2)
                    }
                    if !model.company.isEmpty {
                        CardText(text: model.company, style: style, size: 2.3, weight: .medium, tracking: 0.16,
                                 color: style.muted, uppercase: true)
                    }
                }
                if !model.contacts.isEmpty {
                    CardPlainContacts(contacts: model.contacts, style: style, fontSize: 2.7, spacing: 0.9)
                        .padding(.top, style.u(4.5))
                }
                Spacer(minLength: style.u(2))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.vertical, style.u(7))
            .padding(.trailing, style.u(7))
        }
    }

    @ViewBuilder
    private var deboss: some View {
        if let logo = model.logoData, CardImageDecoder.hasTransparency(logo) {
            CardLogoMark(data: logo, style: .mono, ink: style.debossStyle, width: style.u(30), height: style.u(36))
        } else if let logo = model.logoData {
            // An opaque logo can't be pressed; it sits as printed, smaller.
            CardLogoMark(data: logo, style: .original, ink: style.fg, width: style.u(22), height: style.u(22))
        } else {
            Text(verbatim: model.monogram)
                .font(style.font(34, weight: .heavy))
                .foregroundStyle(style.debossStyle)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .accessibilityHidden(true)
        }
    }
}
