import SwiftUI

/// 4 · Bold — accent company on top, huge first/last name (last in accent), title + first two contact
/// values (no icons) at the bottom; QR bottom-right 20 %.
struct BoldTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: style.horizontalAlignment, spacing: 0) {
            if !model.company.isEmpty {
                CardText(text: model.company, style: style, size: 2.6, weight: .semibold, tracking: 0.18,
                         color: style.accent, uppercase: true)
            }
            Spacer(minLength: 0)
            // CSS line-height 0.95: pull the second line up by the extra system leading.
            VStack(alignment: style.horizontalAlignment, spacing: -style.u(11) * 0.24) {
                CardText(text: model.firstName, style: style, size: 11, weight: .bold, tracking: -0.035,
                         minimumScale: 0.45)
                if !model.lastName.isEmpty {
                    CardText(text: model.lastName, style: style, size: 11, weight: .bold, tracking: -0.035,
                             color: style.accent, minimumScale: 0.45)
                }
            }
            Spacer(minLength: 0)
            CardCapWidth(maxWidth: style.bottomBlockWidth(spec: 60, qrInset: 6.5, qrSize: 20, showsQR: model.showsQR)) {
                VStack(alignment: style.horizontalAlignment, spacing: style.u(0.8)) {
                    if !model.jobTitle.isEmpty {
                        CardText(text: model.jobTitle, style: style, size: 3, color: style.muted)
                    }
                    ForEach(model.boldContacts) { contact in
                        CardText(text: contact.value, style: style, size: 3)
                    }
                }
            }
        }
        .multilineTextAlignment(style.textAlignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.isCentered ? .top : .topLeading)
        .padding(style.u(6.5))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 20).padding(style.u(6.5))
            }
        }
    }
}
