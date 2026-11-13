import ImageIO
import Synchronization
import UIKit

/// Decodes photo/logo data once, downsampled, so grids of thumbnails don't re-decode full images.
enum CardImageDecoder {
    /// Big enough for a 3× PNG export avatar (14 % of 3060 px) and print PDFs.
    static let maxPixelSize = 640

    private static let cache = Mutex<[Data: UIImage]>([:])

    static func image(from data: Data) -> UIImage? {
        if let cached = cache.withLock({ $0[data] }) { return cached }
        guard let image = decode(data) else { return nil }
        cache.withLock { storage in
            if storage.count >= 12 { storage.removeAll(keepingCapacity: true) }
            storage[data] = image
        }
        return image
    }

    /// Whether the image has an alpha channel (a one-colour logo needs a transparent background).
    static func hasTransparency(_ data: Data) -> Bool {
        guard let alpha = image(from: data)?.cgImage?.alphaInfo else { return false }
        return ![.none, .noneSkipFirst, .noneSkipLast].contains(alpha)
    }

    private static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
