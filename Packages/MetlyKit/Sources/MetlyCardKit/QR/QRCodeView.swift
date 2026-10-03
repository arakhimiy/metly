import MetlyCore
import SwiftUI

/// FROZEN PUBLIC API — black-on-white QR code on a white rounded plate.
///
/// - Always black modules on white with a 4-module quiet zone (SPEC: "Always black on a white plate.
///   Logos never go on the code") — there is deliberately no centre logo option.
/// - Drawn as a vector shape, so it stays crisp at any size and in `ImageRenderer`/PDF output.
/// - Square: fills the largest square that fits the proposed size.
public struct QRCodeView: View {
    let payload: String
    let quietZone: Int
    let cornerFraction: CGFloat

    public init(payload: String) {
        self.init(payload: payload, quietZone: QRCodeGenerator.quietZone)
    }

    /// - Parameters:
    ///   - quietZone: light modules around the symbol (keep ≥ 4 for reliable scanning).
    ///   - cornerRadiusFraction: plate corner radius as a fraction of its side (0 = square plate).
    public init(payload: String, quietZone: Int, cornerRadiusFraction: CGFloat = 0.06) {
        self.payload = payload
        self.quietZone = max(quietZone, 0)
        self.cornerFraction = min(max(cornerRadiusFraction, 0), 0.25)
    }

    public var body: some View {
        let matrix = QRCodeGenerator.matrix(for: payload)
        ZStack {
            QRPlateShape(cornerFraction: cornerFraction).fill(.white)
            if let matrix {
                QRModulesShape(matrix: matrix, quietZone: quietZone).fill(.black)
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .foregroundStyle(.black.opacity(0.25))
                    .padding(12)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("QR code"))
        .accessibilityValue(Text(QRPayloadDescription(payload: payload).spoken))
        .accessibilityAddTraits(.isImage)
    }
}

/// What a QR payload means, for VoiceOver.
struct QRPayloadDescription {
    let payload: String

    var spoken: String {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.uppercased().hasPrefix("BEGIN:VCARD") {
            let name = VCardParser.parse(trimmed)?.fullName ?? ""
            return name.isEmpty ? String(localized: "Contact card") : String(localized: "Contact card for \(name)")
        }
        if let url = URL(string: trimmed), let host = url.host() {
            let path = url.path() == "/" ? "" : url.path()
            return String(localized: "Link to \(host + path)")
        }
        return trimmed
    }
}
