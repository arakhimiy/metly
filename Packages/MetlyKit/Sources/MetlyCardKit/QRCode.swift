import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

/// FROZEN PUBLIC API — QR generation (Core Image, error correction M, crisp scaling).
public enum QRCodeGenerator {
    public static func cgImage(for payload: String, scale: CGFloat = 12) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: scale, y: scale)) else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    public static func uiImage(for payload: String, scale: CGFloat = 12) -> UIImage? {
        cgImage(for: payload, scale: scale).map { UIImage(cgImage: $0) }
    }
}

/// Black-on-white QR with quiet zone, scales without blur.
public struct QRCodeView: View {
    let payload: String

    public init(payload: String) { self.payload = payload }

    public var body: some View {
        Group {
            if let image = QRCodeGenerator.uiImage(for: payload) {
                Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "qrcode").resizable().scaledToFit().foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityLabel("QR code")
    }
}
