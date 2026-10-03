import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Turns a picked photo into a small JPEG for `Profile.photoData` (strips EXIF/location metadata).
nonisolated enum ImageDownscaler {
    /// - Parameters:
    ///   - maxPixelSize: longest side of the result, in pixels.
    ///   - quality: JPEG compression quality (0…1).
    @concurrent
    static func jpegData(from data: Data, maxPixelSize: Int = 640, quality: Double = 0.8) async -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions) else { return nil }

        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,   // bake in EXIF orientation
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
