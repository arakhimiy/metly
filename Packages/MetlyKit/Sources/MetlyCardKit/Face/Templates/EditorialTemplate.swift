import SwiftUI

/// 9 · Editorial (Pro) — forced New York; "No. 01" / company header with a rule, large italic name,
/// accent title, contact values without icons; QR bottom-right 20 %.
struct EditorialTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: style.u(3)) {
                CardText(text: "No. 01", style: style, size: 2.5, tracking: 0.18, color: style.muted, uppercase: true)
                Spacer(minLength: 0)
                if !model.company.isEmpty {
                    CardText(text: model.company, style: style, size: 2.5, tracking: 0.18, color: style.muted,
                             uppercase: true)
                }
            }
            .padding(.bottom, style.u(1.8))
            .overlay(alignment: .bottom) {
                Rectangle().fill(style.rule).frame(height: style.hairline)
            }

            Text(verbatim: model.fullName)
                .font(style.font(9).italic())
                .tracking(style.tracking(-0.01, size: 9))
                .lineLimit(2)
                .minimumScaleFactor(0.7)
                .padding(.top, style.u(5))

            if !model.jobTitle.isEmpty {
                CardCapWidth(maxWidth: model.showsQR ? style.u(64) : style.width) {
                    CardText(text: model.jobTitle, style: style, size: 3.4, color: style.accent)
                }
                .padding(.top, style.u(1.4))
            }
            Spacer(minLength: 0)
            CardCapWidth(maxWidth: style.u(58)) {
                VStack(alignment: .leading, spacing: style.u(0.8)) {
                    ForEach(model.contacts) { contact in
                        CardText(text: contact.value, style: style, size: 3.1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(style.u(6.5))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 20, cornerRadius: 1).padding(style.u(6.5))
            }
        }
    }
}
