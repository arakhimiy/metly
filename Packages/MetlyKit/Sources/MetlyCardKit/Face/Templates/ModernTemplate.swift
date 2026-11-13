import SwiftUI

/// Foil (`modern`, Pro) — matte stock with an iridescent foil bar, the name in spaced capitals and the
/// company as an outlined vertical wordmark on the right edge. [PHENOMINAL]
struct ModernTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle
    let foil: CardFoil

    var body: some View {
        let qrSide: CGFloat = 14
        HStack(alignment: .top, spacing: style.u(4.5)) {
            VStack(alignment: .leading) {
                CardFoilBlock(foil: foil, cornerRadius: style.u(0.4))
                    .frame(width: style.u(6.5), height: style.u(26))
                Spacer(minLength: 0)
                if let logo = model.logoData {
                    CardLogoMark(data: logo, style: .mono, ink: foil.gradient, width: style.u(6.5),
                                 height: style.u(6.5), alignment: .bottomLeading)
                }
            }
            VStack(alignment: .leading, spacing: 0) {
                CardText(text: model.fullName, style: style, size: 4.2, weight: .semibold, tracking: 0.06,
                         lineLimit: 2, minimumScale: 0.6, uppercase: true)
                if !model.jobTitle.isEmpty {
                    Text(verbatim: model.jobTitle)
                        .font(style.font(3).italic())
                        .foregroundStyle(style.fg.opacity(0.85))
                        .lineLimit(2)
                        .padding(.top, style.u(1.2))
                }
                Spacer(minLength: style.u(3))
                CardPlainContacts(contacts: model.contacts, style: style, fontSize: 2.8, weight: .medium, spacing: 1.1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            if !model.company.isEmpty {
                verticalWordmark(reserving: model.showsQR ? qrSide + 3 : 0)
            }
        }
        .padding(style.u(8))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: qrSide, cornerRadius: 1.2).padding(style.u(6))
            }
        }
    }

    /// The company set bottom-to-top along the right edge, above the QR when there is one.
    private func verticalWordmark(reserving bottom: CGFloat) -> some View {
        let length = style.height - style.u(16) - style.u(bottom)
        let thickness = style.u(7)
        return CardOutlinedText(text: model.company, font: style.font(6.2, weight: .heavy),
                                tracking: style.tracking(0.1, size: 6.2), stroke: style.fg, fill: style.bg,
                                lineWidth: max(style.hairline * 0.7, 0.4))
            .frame(width: max(length, 1), height: thickness, alignment: .trailing)
            .rotationEffect(.degrees(-90))
            .frame(width: thickness, height: max(length, 1))
            .frame(maxHeight: .infinity, alignment: .top)
    }
}
