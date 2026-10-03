import CoreImage
import CoreImage.CIFilterBuiltins
import Synchronization
import UIKit

/// FROZEN PUBLIC API — QR generation (Core Image, error correction M).
///
/// Core Image only encodes; the module matrix is read back once per payload, cached, and then
/// drawn crisply at any size (vector `Shape` on screen / in PDFs, pixel-exact bitmaps for images)
/// with the 4-module quiet zone required by SPEC §2.5.25.
public enum QRCodeGenerator {
    /// Quiet zone in modules on every side (ISO/IEC 18004 minimum).
    public static let quietZone = 4

    /// Black-on-white bitmap with a 4-module quiet zone; `scale` = pixels per module.
    public static func cgImage(for payload: String, scale: CGFloat = 12) -> CGImage? {
        guard let matrix = matrix(for: payload) else { return nil }
        return render(matrix, pixelsPerModule: max(Int(scale.rounded()), 1), quietZone: quietZone)
    }

    public static func uiImage(for payload: String, scale: CGFloat = 12) -> UIImage? {
        cgImage(for: payload, scale: scale).map { UIImage(cgImage: $0) }
    }

    /// Module matrix for `payload` at error correction level M, or nil when it does not fit a QR code.
    public static func matrix(for payload: String) -> QRMatrix? {
        guard !payload.isEmpty else { return nil }
        if let cached = cache.withLock({ $0[payload] }) { return cached }
        guard let matrix = makeMatrix(payload) else { return nil }
        cache.withLock { storage in
            if storage.count >= 64 { storage.removeAll(keepingCapacity: true) }
            storage[payload] = matrix
        }
        return matrix
    }

    // MARK: - Private

    private static let cache = Mutex<[String: QRMatrix]>([:])

    /// CIContext is thread-safe (Sendable); it is created once because it is expensive.
    private static let context = CIContext(options: [
        .workingColorSpace: NSNull(), .outputColorSpace: NSNull(), .cacheIntermediates: false,
    ])

    private static func makeMatrix(_ payload: String) -> QRMatrix? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let extent = output.extent.integral
        let width = Int(extent.width), height = Int(extent.height)
        guard width > 0, height > 0 else { return nil }

        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        pixels.withUnsafeMutableBytes { buffer in
            context.render(output, toBitmap: buffer.baseAddress!, rowBytes: width * 4, bounds: extent,
                           format: .RGBA8, colorSpace: nil)
        }
        func isDark(_ x: Int, _ y: Int) -> Bool { pixels[(y * width + x) * 4] < 128 }

        // Core Image adds its own margin; the symbol is the bounding box of dark pixels
        // (finder patterns guarantee it spans the full symbol).
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where isDark(x, y) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        let size = maxX - minX + 1
        guard maxX >= 0, size == maxY - minY + 1, size >= 21 else { return nil }

        var modules = [Bool](repeating: false, count: size * size)
        for y in 0..<size {
            for x in 0..<size {
                modules[y * size + x] = isDark(minX + x, minY + y)
            }
        }
        let matrix = QRMatrix(size: size, modules: modules)
        if matrix.isUpright { return matrix }
        let flipped = matrix.flippedVertically()   // bitmap rows came back bottom-up
        return flipped.isUpright ? flipped : nil
    }

    private static func render(_ matrix: QRMatrix, pixelsPerModule: Int, quietZone: Int) -> CGImage? {
        let side = (matrix.size + 2 * quietZone) * pixelsPerModule
        guard let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
        else { return nil }
        context.setShouldAntialias(false)
        context.interpolationQuality = .none
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        context.setFillColor(gray: 0, alpha: 1)
        let unit = CGFloat(pixelsPerModule)
        for run in matrix.darkRuns {
            // CoreGraphics' origin is bottom-left: flip rows so the image is upright.
            let row = matrix.size - 1 - run.y
            context.fill(CGRect(x: CGFloat(run.x + quietZone) * unit, y: CGFloat(row + quietZone) * unit,
                                width: CGFloat(run.length) * unit, height: unit))
        }
        return context.makeImage()
    }
}
