import SwiftUI

/// 6 · Split — accent panel on the left 36 % (drawn by `CardEdgeDecor`) holding the avatar and QR (21 %);
/// name, title, company and contacts on the right.
struct SplitTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: style.u(3.4)) {
                CardAvatar(photoData: model.photoData, initials: model.initials, style: style, size: 13,
                           initialsSize: 4.6, fill: style.bg, textColor: style.fg)
                if model.showsQR {
                    CardQRPlate(payload: model.qrPayload, style: style, size: 21)
                }
            }
            .frame(width: style.u(36))
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: style.u(1)) {
                    CardText(text: model.fullName, style: style, size: 5.6, weight: .semibold, tracking: -0.02,
                             minimumScale: 0.6)
                    if !model.jobTitle.isEmpty {
                        CardText(text: model.jobTitle, style: style, size: 3, color: style.muted, lineLimit: 2)
                    }
                    if !model.company.isEmpty {
                        CardText(text: model.company, style: style, size: 2.6, tracking: 0.14, color: style.accent,
                                 uppercase: true)
                            .padding(.top, style.u(1))
                    }
                }
                Spacer(minLength: 0)
                CardContactList(contacts: model.contacts, style: style, fontSize: 2.9, iconSize: 3.2,
                                maxWidth: style.u(64 - 13))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(style.u(6.5))
        }
    }
}
