import SwiftUI

/// 5 · Gradient — always gradient fill; company in an outlined pill, name + title in the middle,
/// contacts with foreground-coloured icons at the bottom; QR bottom-right 23 %.
struct GradientTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: style.horizontalAlignment, spacing: 0) {
            if !model.company.isEmpty {
                CardText(text: model.company, style: style, size: 2.6)
                    .padding(.vertical, style.u(0.9))
                    .padding(.horizontal, style.u(2.6))
                    .overlay {
                        Capsule().strokeBorder(style.rule, lineWidth: style.hairline)
                    }
            }
            Spacer(minLength: 0)
            VStack(alignment: style.horizontalAlignment, spacing: style.u(1)) {
                CardText(text: model.fullName, style: style, size: 7, weight: .semibold, tracking: -0.025,
                         minimumScale: 0.6)
                if !model.jobTitle.isEmpty {
                    CardText(text: model.jobTitle, style: style, size: 3.2, color: style.muted)
                }
            }
            Spacer(minLength: 0)
            CardContactList(contacts: model.contacts, style: style, spacing: 0.9,
                            maxWidth: style.bottomBlockWidth(spec: 58, qrInset: 6, qrSize: 23, showsQR: model.showsQR),
                            iconColor: style.fg)
        }
        .multilineTextAlignment(style.textAlignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.isCentered ? .top : .topLeading)
        .padding(style.u(7))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 23).padding(style.u(6))
            }
        }
    }
}
