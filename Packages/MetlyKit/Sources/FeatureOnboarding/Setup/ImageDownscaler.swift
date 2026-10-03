import Foundation
import ImageIO
import UIKit

/// Turns a picked photo (often a 12 MP HEIC) into a small JPEG for the profile/card avatar.
nonisolated enum ImageDownscaler {
    /// Decodes off the main actor with ImageIO (memory-friendly, applies EXIF orientation).
    @concurrent
    static func jpegData(from data: Data, maxPixelSize: Int = 800, compressionQuality: CGFloat = 0.8) async -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: image).jpegData(compressionQuality: compressionQuality)
    }
}
