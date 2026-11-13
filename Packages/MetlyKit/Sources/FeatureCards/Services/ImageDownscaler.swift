import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a picked photo/logo into a small image for `Profile.photoData` / `logoData`
/// (EXIF orientation baked in, location metadata dropped). Runs off the main actor.
nonisolated enum ImageDownscaler {
    enum Format: Sendable {
        /// Profile photos.
        case jpeg(quality: Double)
        /// Logos keep their transparency.
        case png

        var type: UTType {
            switch self {
            case .jpeg: .jpeg
            case .png: .png
            }
        }
    }

    /// - Parameter trimsMargins: crop away a transparent or uniform-colour border first (logos arrive padded,
    ///   which makes them look tiny on a card).
    @concurrent
    static func downscale(_ data: Data, maxPixelSize: Int, format: Format, trimsMargins: Bool = false) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = trimsMargins ? (LogoTrimmer.trimmed(thumbnail) ?? thumbnail) : thumbnail

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, format.type.identifier as CFString, 1, nil)
        else { return nil }
        var properties: [CFString: Any] = [:]
        if case .jpeg(let quality) = format { properties[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Finds a logo's content box: every pixel that differs from the border colour (transparent, or the
/// uniform white/black box most JPG logos come in), plus a small breathing margin.
nonisolated enum LogoTrimmer {
    /// The image cropped to its content, or nil when there is nothing to trim (or it's all background).
    static func trimmed(_ image: CGImage) -> CGImage? {
        guard let box = contentBox(image) else { return nil }
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        guard box != full else { return nil }
        return image.cropping(to: box)
    }

    static func contentBox(_ image: CGImage) -> CGRect? {
        let width = image.width, height = image.height
        guard width > 2, height > 2 else { return nil }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                          bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drawn else { return nil }

        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
            let i = (y * width + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
        }
        let corner = pixel(0, 0)
        func isBackground(_ p: (Int, Int, Int, Int)) -> Bool {
            if corner.3 < 16 { return p.3 < 16 }
            return abs(p.0 - corner.0) + abs(p.1 - corner.1) + abs(p.2 - corner.2) < 36 && abs(p.3 - corner.3) < 16
        }
        // Only trim a real border: all four corners have to be background.
        guard [pixel(width - 1, 0), pixel(0, height - 1), pixel(width - 1, height - 1)].allSatisfy(isBackground) else {
            return nil
        }
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            for x in 0..<width where !isBackground(pixel(x, y)) {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let margin = max((maxX - minX + maxY - minY) / 100, 1)
        let x0 = max(minX - margin, 0), y0 = max(minY - margin, 0)
        let x1 = min(maxX + margin, width - 1), y1 = min(maxY + margin, height - 1)
        return CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
    }
}
