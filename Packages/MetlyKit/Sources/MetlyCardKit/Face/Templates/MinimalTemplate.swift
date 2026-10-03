import SwiftUI

/// 1 · Minimal — name + role on top (max 62 %), contacts at the bottom (max 58 %), QR bottom-right 24 %.
struct MinimalTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: style.horizontalAlignment, spacing: 0) {
            CardCapWidth(maxWidth: style.u(62)) {
                VStack(alignment: style.horizontalAlignment, spacing: style.u(1.2)) {
                    CardText(text: model.fullName, style: style, size: 6.6, weight: .semibold, tracking: -0.02,
                             minimumScale: 0.6)
                    if !model.role.isEmpty {
                        CardText(text: model.role, style: style, size: 3.3, color: style.muted, lineLimit: 2)
                    }
                }
            }
            Spacer(minLength: 0)
            CardContactList(contacts: model.contacts, style: style, fontSize: 3.1, iconSize: 3.4,
                            maxWidth: style.bottomBlockWidth(spec: 58, qrInset: 6, qrSize: 24, showsQR: model.showsQR))
        }
        .multilineTextAlignment(style.textAlignment)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: style.isCentered ? .top : .topLeading)
        .padding(style.u(7))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 24).padding(style.u(6))
            }
        }
    }
}
