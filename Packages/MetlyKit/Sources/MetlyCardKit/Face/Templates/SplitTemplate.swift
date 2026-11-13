import SwiftUI

/// Duotone (`split`) — a flat accent panel on the left 36 % (drawn by `CardEdgeDecor`) holding the logo,
/// photo or initials and the QR; name, title, company, an accent rule and contacts on the right.
struct SplitTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: style.u(4)) {
                panelMark
                if model.showsQR {
                    CardQRPlate(payload: model.qrPayload, style: style, size: 17, cornerRadius: 1.4)
                }
            }
            .frame(width: style.u(36))
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: style.u(0.8)) {
                    CardText(text: model.fullName, style: style, size: 5.2, weight: .semibold, tracking: -0.015,
                             lineLimit: 2, minimumScale: 0.6)
                    if !model.jobTitle.isEmpty {
                        CardText(text: model.jobTitle, style: style, size: 2.9, color: style.muted, lineLimit: 2)
                    }
                    if !model.company.isEmpty {
                        CardText(text: model.company, style: style, size: 2.9, color: style.muted)
                    }
                }
                Rectangle().fill(style.accent).frame(width: style.u(7), height: max(style.u(0.35), style.hairline))
                    .padding(.vertical, style.u(3.4))
                CardContactList(contacts: model.contacts, style: style, fontSize: 2.7, iconSize: 2.9, spacing: 1,
                                maxWidth: style.u(50))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .padding(.leading, style.u(6.5))
            .padding(.trailing, style.u(6))
        }
    }

    /// Logo first (it's a brand panel), then the photo, then initials.
    @ViewBuilder
    private var panelMark: some View {
        let onPanel = style.colors.accent.isDark ? Color.white : style.bg
        if let logo = model.logoData {
            CardLogoMark(data: logo, style: .mono, ink: onPanel, width: style.u(20),
                         height: style.u(model.showsQR ? 10 : 15))
        } else {
            CardAvatar(photoData: model.photoData, initials: model.initials, style: style,
                       size: model.showsQR ? 11 : 15, initialsSize: model.showsQR ? 4 : 5.4,
                       fill: onPanel.opacity(0.18), textColor: onPanel)
        }
    }
}
