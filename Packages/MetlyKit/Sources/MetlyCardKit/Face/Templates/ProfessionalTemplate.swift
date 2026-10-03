import SwiftUI

/// 2 · Professional — logo (or monogram tile) + tracked company on top; name, title, accent bar and
/// contacts at the bottom; QR bottom-right 22 %.
struct ProfessionalTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: style.u(3)) {
                CardLogoTile(logoData: model.logoData, monogram: model.monogram, style: style)
                Spacer(minLength: 0)
                if !model.company.isEmpty {
                    CardText(text: model.company, style: style, size: 2.6, tracking: 0.16, color: style.muted,
                             uppercase: true)
                }
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: style.u(1)) {
                CardText(text: model.fullName, style: style, size: 6, weight: .semibold, tracking: -0.02,
                         minimumScale: 0.6)
                if !model.jobTitle.isEmpty {
                    CardCapWidth(maxWidth: model.showsQR ? style.u(63) : style.width) {
                        CardText(text: model.jobTitle, style: style, size: 3.2, color: style.muted)
                    }
                }
                Rectangle()
                    .fill(style.accent)
                    .frame(width: style.u(9), height: style.u(0.6))
                    .padding(.top, style.u(1.6))
                    .padding(.bottom, style.u(2.2))
            }
            CardContactList(contacts: model.contacts, style: style, maxWidth: style.u(58))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(style.u(6.5))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 22).padding(style.u(6.5))
            }
        }
    }
}
