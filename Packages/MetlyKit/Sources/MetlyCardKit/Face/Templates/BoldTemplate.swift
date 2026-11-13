import SwiftUI

/// Wordmark (`bold`) — pure type: the company (or first name) huge and fitted to one line, a spaced
/// tagline, two contacts bottom-left and the logo as a corner mark. [MOCKUP card stack]
struct BoldTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: style.horizontalAlignment, spacing: 0) {
            CardText(text: model.wordmark, style: style, size: 12, weight: .heavy, tracking: -0.03,
                     minimumScale: 0.3, uppercase: true)
            if !model.jobTitle.isEmpty {
                CardText(text: model.jobTitle, style: style, size: 2.3, weight: .semibold, tracking: 0.24,
                         color: style.muted, uppercase: true)
                    .padding(.top, style.u(2.2))
            }
            Spacer(minLength: style.u(2))
            HStack(alignment: .bottom, spacing: style.u(4)) {
                VStack(alignment: .leading, spacing: style.u(0.8)) {
                    if !model.company.isEmpty {
                        CardText(text: model.fullName, style: style, size: 3.1, weight: .bold, minimumScale: 0.7)
                    }
                    CardPlainContacts(contacts: model.boldContacts, style: style, fontSize: 2.8, spacing: 0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if model.showsQR {
                    CardQRPlate(payload: model.qrPayload, style: style, size: 15, cornerRadius: 1.4)
                } else if let logo = model.logoData {
                    CardLogoMark(data: logo, style: model.logoStyle, ink: style.fg, width: style.u(9), height: style.u(9),
                                 alignment: .bottomTrailing)
                }
            }
        }
        .multilineTextAlignment(style.textAlignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.isCentered ? .top : .topLeading)
        .padding(style.u(8))
    }
}
