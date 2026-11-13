import SwiftUI

/// Centered (`stack`) — a formal centred card: logo or photo on top, name, title, a short accent rule,
/// and the contacts on one line (wrapping to two).
struct StackTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        VStack(spacing: 0) {
            mark
            CardText(text: model.fullName, style: style, size: 5.4, weight: .semibold, tracking: -0.01, minimumScale: 0.6)
                .padding(.top, style.u(2.6))
            let role = model.role
            if !role.isEmpty {
                CardText(text: role, style: style, size: 2.8, color: style.muted, lineLimit: 2)
                    .padding(.top, style.u(0.8))
            }
            if !model.contacts.isEmpty {
                Rectangle().fill(style.accent).frame(width: style.u(8), height: max(style.u(0.35), style.hairline))
                    .padding(.vertical, style.u(3))
                CardFlowLayout(horizontalSpacing: style.u(3.2), verticalSpacing: style.u(0.9)) {
                    ForEach(model.contacts) { contact in
                        CardContactValue(contact: contact, style: style, fontSize: 2.6)
                    }
                }
                .frame(maxWidth: style.u(84))
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, style.u(8))
        .padding(.vertical, style.u(6))
        .overlay(alignment: .topTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 12, cornerRadius: 1.2).padding(style.u(5.5))
            }
        }
    }

    @ViewBuilder
    private var mark: some View {
        if let logo = model.logoData {
            CardLogoMark(data: logo, style: model.logoStyle, ink: style.accent, width: style.u(24), height: style.u(8.5))
        } else if model.photoData != nil {
            CardAvatar(photoData: model.photoData, initials: model.initials, style: style, size: 11, initialsSize: 4,
                       fill: style.panelTint, textColor: style.fg)
        }
    }
}
