import SwiftUI

/// 8 · Stack — centred column (avatar, name, role, inline wrapped contacts); small QR top-right 15 %.
struct StackTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(spacing: style.u(1.4)) {
            CardAvatar(photoData: model.photoData, initials: model.initials, style: style, size: 13,
                       initialsSize: 4.6, fill: style.panelTint, textColor: style.fg)
                .padding(.bottom, style.u(1))
            CardText(text: model.fullName, style: style, size: 5.6, weight: .semibold, tracking: -0.02,
                     minimumScale: 0.6)
            if !model.role.isEmpty {
                CardText(text: model.role, style: style, size: 3, color: style.muted, lineLimit: 2)
            }
            if !model.contacts.isEmpty {
                CardFlowLayout(horizontalSpacing: style.u(3), verticalSpacing: style.u(0.6)) {
                    ForEach(model.contacts) { contact in
                        HStack(spacing: style.u(1)) {
                            Image(systemName: contact.kind.symbolName)
                                .font(.system(size: max(style.u(2.6), 0.5)))
                                .foregroundStyle(style.accent)
                            CardText(text: contact.value, style: style, size: 2.7)
                        }
                    }
                }
                .padding(.top, style.u(1.6))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, style.u(6))
        .padding(.horizontal, style.u(20))
        .overlay(alignment: .topTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 15, cornerRadius: 1.6).padding(style.u(4.5))
            }
        }
    }
}
