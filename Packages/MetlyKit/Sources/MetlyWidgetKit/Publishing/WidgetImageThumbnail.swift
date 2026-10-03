import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Downscales profile photo / logo before they go into the snapshot (widgets have a tight memory
/// budget, and a card face in a medium widget never needs more than ~200 px of avatar).
nonisolated public enum WidgetImageThumbnail {
    public static let maxPixelSize = 240

    /// PNG (keeps logo transparency), or nil when `data` is not an image.
    public static func make(from data: Data, maxPixelSize: Int = maxPixelSize) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}

/// Remembers the last few thumbnails so republishing after every save doesn't re-decode the photo.
@MainActor
final class WidgetThumbnailCache {
    private var entries: [(source: Data, thumbnail: Data?)] = []

    func thumbnail(for data: Data) -> Data? {
        if let hit = entries.first(where: { $0.source == data }) { return hit.thumbnail }
        let thumbnail = WidgetImageThumbnail.make(from: data)
        entries.append((data, thumbnail))
        if entries.count > 4 { entries.removeFirst() }
        return thumbnail
    }
}
