import SwiftUI

/// Classic (`minimal`) — uncoated stock. Logo / company wordmark top-left, name + title bottom-left,
/// a labelled contact column bottom-right; QR top-right when on. [MOCK-UP card back]
struct MinimalTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: style.u(2.2)) {
                if let logo = model.logoData {
                    CardLogoMark(data: logo, style: model.logoStyle, ink: style.fg, width: style.u(14), height: style.u(6),
                                 alignment: .leading)
                        .fixedSize()
                }
                if !model.company.isEmpty {
                    CardText(text: model.company, style: style, size: 2.5, weight: .semibold, tracking: 0.2, uppercase: true)
                }
            }
            .frame(maxWidth: style.u(model.showsQR ? 62 : 84), alignment: .leading)
            Spacer(minLength: style.u(2))
            HStack(alignment: .bottom, spacing: style.u(4)) {
                VStack(alignment: .leading, spacing: style.u(1.2)) {
                    CardText(text: model.fullName, style: style, size: 6.2, weight: .semibold, tracking: -0.015,
                             lineLimit: 2, minimumScale: 0.6)
                    if !model.jobTitle.isEmpty {
                        CardText(text: model.jobTitle, style: style, size: 3, color: style.muted, lineLimit: 2)
                    }
                }
                Spacer(minLength: 0)
                if !model.contacts.isEmpty {
                    CardCapWidth(maxWidth: style.u(50)) {
                        CardLabelledContacts(contacts: model.contacts, style: style)
                    }
                    .layoutPriority(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(style.u(8))
        .overlay(alignment: .topTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 15, cornerRadius: 1.4).padding(style.u(7))
            }
        }
    }
}
