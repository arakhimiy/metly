import MetlyCardKit
import SwiftUI
import WidgetKit

/// A QR code that stays scannable in every widget rendering mode.
///
/// • Full color: CardKit's vector `QRCodeView` (black modules on a white plate).
/// • Accented (tinted / clear Home Screen): a pixel-exact bitmap kept in full color, so tinting can't
///   flatten the modules and the plate into one solid square.
/// • Vibrant (Lock Screen): the plate as one opaque shape with the modules cut out — vibrancy maps
///   opaque to bright, so the code keeps dark-on-light polarity over the accessory backdrop.
public struct WidgetQRCode: View {
    let payload: String
    let quietZone: Int
    let isDimmed: Bool
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.redactionReasons) private var redactionReasons

    /// - Parameters:
    ///   - quietZone: light modules around the symbol (4 = ISO minimum; 2 is fine on tiny accessory widgets).
    ///   - isDimmed: paused link — drawn faintly, like QR_FULLSCREEN.
    public init(payload: String, quietZone: Int = QRCodeGenerator.quietZone, isDimmed: Bool = false) {
        self.payload = payload
        self.quietZone = quietZone
        self.isDimmed = isDimmed
    }

    static let cornerFraction: CGFloat = 0.08

    public var body: some View {
        code
            .aspectRatio(1, contentMode: .fit)
            .opacity(isDimmed ? 0.18 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("QR code"))
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var code: some View {
        if redactionReasons.contains(.placeholder) {
            WidgetQRPlateShape(cornerFraction: Self.cornerFraction).fill(.quaternary)
        } else if renderingMode == .accented, let image = QRCodeGenerator.uiImage(for: payload, scale: 1) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .widgetAccentedRenderingMode(.fullColor)
                .clipShape(WidgetQRPlateShape(cornerFraction: Self.cornerFraction))
        } else if renderingMode == .vibrant {
            WidgetQRKnockoutShape(payload: payload, quietZone: quietZone, cornerFraction: Self.cornerFraction)
                .fill(.white, style: FillStyle(eoFill: true))
        } else {
            QRCodeView(payload: payload, quietZone: quietZone, cornerRadiusFraction: Self.cornerFraction)
        }
    }
}

/// Square plate with continuous corners; radius is a fraction of the side.
nonisolated struct WidgetQRPlateShape: Shape {
    var cornerFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return Path(roundedRect: square, cornerRadius: side * cornerFraction, style: .continuous)
    }
}

/// The QR plate with every dark module as a hole (fill with `eoFill`).
nonisolated struct WidgetQRKnockoutShape: Shape {
    let payload: String
    let quietZone: Int
    let cornerFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = WidgetQRPlateShape(cornerFraction: cornerFraction).path(in: rect)
        guard let matrix = QRCodeGenerator.matrix(for: payload) else { return path }
        let side = min(rect.width, rect.height)
        let unit = side / CGFloat(matrix.size + 2 * quietZone)
        let originX = rect.midX - side / 2 + unit * CGFloat(quietZone)
        let originY = rect.midY - side / 2 + unit * CGFloat(quietZone)
        for y in 0..<matrix.size {
            var x = 0
            while x < matrix.size {
                guard matrix[x, y] else { x += 1; continue }
                let start = x
                while x < matrix.size, matrix[x, y] { x += 1 }
                path.addRect(CGRect(x: originX + CGFloat(start) * unit, y: originY + CGFloat(y) * unit,
                                    width: CGFloat(x - start) * unit, height: unit))
            }
        }
        return path
    }
}
