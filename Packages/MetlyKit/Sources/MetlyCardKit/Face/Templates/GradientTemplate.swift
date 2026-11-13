import SwiftUI

/// Aurora (`gradient`, Pro) — a vivid three-stop gradient with contour lines (drawn by `CardEdgeDecor`),
/// the name as a widely spaced wordmark in the middle, a link and the title along the bottom. [BROOKS]
struct GradientTemplate: View {
    let model: CardFaceModel
    let style: CardFaceStyle
    let ink: Color

    var body: some View {
        ZStack {
            CardText(text: model.fullName, style: style, size: 6.6, weight: .medium, tracking: 0.3, color: ink,
                     minimumScale: 0.35, uppercase: true)
                .frame(width: style.u(model.showsQR ? 64 : 84))
                .offset(x: model.showsQR ? -style.u(10) : 0)
            VStack {
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: style.u(4)) {
                    if let link {
                        CardText(text: link.value, style: style, size: 2.6, tracking: 0.06, color: ink.opacity(0.92))
                    }
                    Spacer(minLength: 0)
                    let caption = [model.jobTitle, model.company].filter { !$0.isEmpty }.joined(separator: " · ")
                    if !caption.isEmpty {
                        CardText(text: caption, style: style, size: 2.6, tracking: 0.06, color: ink.opacity(0.92))
                            .layoutPriority(-1)
                    }
                }
            }
            .padding(.horizontal, style.u(8))
            .padding(.bottom, style.u(7))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topTrailing) {
            if model.showsQR {
                CardQRPlate(payload: model.qrPayload, style: style, size: 14, cornerRadius: 1.4).padding(style.u(7))
            }
        }
    }

    /// The website when the card shows one, else its first contact.
    private var link: CardFaceModel.Contact? {
        model.contacts.first { $0.kind == .website } ?? model.contacts.first
    }
}
