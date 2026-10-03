import SwiftUI

/// The card face QR: white rounded square, black modules, 4-module quiet zone
/// (a version-2 code is exactly the 33-module viewbox of Appendix B).
struct CardQRPlate: View {
    let payload: String
    let style: CardFaceStyle
    /// Side, % of card width.
    let size: CGFloat
    /// Corner radius, % of card width.
    var cornerRadius: CGFloat = 2

    var body: some View {
        let side = style.u(size)
        QRCodeView(payload: payload, quietZone: QRCodeGenerator.quietZone,
                   cornerRadiusFraction: side > 0 ? style.u(cornerRadius) / side : 0)
            .frame(width: side, height: side)
            .accessibilityHidden(true)
    }
}
