import MetlyCore
import SwiftUI

/// Vertical metrics of the Lock Screen wallpaper: the top ~36 % stays clear for the clock and
/// widgets, the bottom 10 % for the home indicator / quick actions; QR + card fill the rest.
struct LockScreenLayout {
    let top: CGFloat
    let qrSide: CGFloat
    let captionSize: CGFloat
    let captionGap: CGFloat
    let cardGap: CGFloat
    let cardWidth: CGFloat

    init(size: CGSize) {
        let width = size.width, height = size.height
        top = height * 0.36
        let available = height - top - height * 0.10
        let qr = width * 0.52, caption = width * 0.036, captionGap = width * 0.03
        let cardGap = width * 0.07, card = width * 0.76
        let needed = qr + captionGap + caption * 1.3 + cardGap + card / CardFaceView.aspectRatio
        let k = min(1, max(available, 0) / needed)
        qrSide = qr * k
        captionSize = caption * k
        self.captionGap = captionGap * k
        self.cardGap = cardGap * k
        cardWidth = card * k
    }
}

/// Lock Screen wallpaper: palette gradient, large QR on a white plate, "Scan to connect" and the
/// card face (without its own QR). Fixed sizes relative to the image — it is rendered, not laid out.
struct LockScreenWallpaperView: View {
    let design: CardDesign
    let content: CardFaceContent
    let size: CGSize

    var body: some View {
        let colors = design.colors
        let layout = LockScreenLayout(size: size)
        let payload = CardFaceModel(design: design, content: content).qrPayload
        ZStack(alignment: .top) {
            Rectangle().fill(CardGradient.linear140(from: colors.background, to: colors.gradientEnd, size: size))
            VStack(spacing: 0) {
                QRCodeView(payload: payload, quietZone: QRCodeGenerator.quietZone, cornerRadiusFraction: 0.06)
                    .frame(width: layout.qrSide, height: layout.qrSide)
                    .background {
                        // Shadow on a backing shape only — a shadow on the QR itself would blur every module.
                        QRPlateShape(cornerFraction: 0.06)
                            .fill(.white)
                            .shadow(color: .black.opacity(0.18), radius: layout.qrSide * 0.04, y: layout.qrSide * 0.015)
                    }
                Text("Scan to connect")
                    .font(.system(size: max(layout.captionSize, 1), weight: .semibold))
                    .foregroundStyle(colors.foreground.color)
                    .padding(.top, layout.captionGap)
                CardFaceCanvas(design: faceDesign, content: content, width: layout.cardWidth)
                    .background {
                        CardFaceShape()
                            .fill(colors.background.color)
                            .shadow(color: .black.opacity(0.25), radius: layout.cardWidth * 0.03, y: layout.cardWidth * 0.015)
                    }
                    .padding(.top, layout.cardGap)
            }
            .padding(.top, layout.top)
        }
        .frame(width: size.width, height: size.height)
    }

    /// The big QR replaces the card's own plate.
    private var faceDesign: CardDesign {
        var copy = design
        copy.showQR = false
        return copy
    }
}
