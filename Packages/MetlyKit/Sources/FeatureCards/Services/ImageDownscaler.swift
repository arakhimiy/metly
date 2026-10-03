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

    @concurrent
    static func downscale(_ data: Data, maxPixelSize: Int, format: Format) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }

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
