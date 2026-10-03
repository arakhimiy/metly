import SwiftUI

/// 3 · Modern — accent stripe on the left edge (drawn by `CardEdgeDecor`), avatar + name/role header,
/// contacts at the bottom; QR bottom-right 22 %.
struct ModernTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: style.u(3.4)) {
                CardAvatar(photoData: model.photoData, initials: model.initials, style: style, size: 14,
                           initialsSize: 5, fill: style.panelTint, textColor: style.fg)
                VStack(alignment: .leading, spacing: style.u(1)) {
                    CardText(text: model.fullName, style: style, size: 5.6, weight: .semibold, tracking: -0.02,
                             minimumScale: 0.6)
                    if !model.role.isEmpty {
                        CardText(text: model.role, style: style, size: 3, color: style.muted, lineLimit: 2)
                    }
                }
            }
            Spacer(minLength: 0)
            CardContactList(contacts: model.contacts, style: style, maxWidth: style.u(56))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, style.u(7))
        .padding(.trailing, style.u(7))
        .padding(.leading, style.u(9.5))
        .overlay(alignment: .bottomTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 22).padding(style.u(6))
            }
        }
    }
}
