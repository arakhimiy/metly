import Foundation
import ImageIO
import Testing
import UIKit
@testable import FeatureProfile

@Suite("Profile photo downscaling")
struct ImageDownscalerTests {
    private func pngData(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
        return renderer.pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func pixelSize(of data: Data) -> CGSize? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        return CGSize(width: image.width, height: image.height)
    }

    @Test func largePhotoIsShrunkToTheMaximumSide() async throws {
        let jpeg = try #require(await ImageDownscaler.jpegData(from: pngData(width: 2400, height: 1600), maxPixelSize: 600))
        let size = try #require(pixelSize(of: jpeg))
        #expect(max(size.width, size.height) == 600)
        #expect(size.width > size.height)
        // JPEG magic number.
        #expect(jpeg.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func smallPhotoIsNotUpscaled() async throws {
        let jpeg = try #require(await ImageDownscaler.jpegData(from: pngData(width: 200, height: 300), maxPixelSize: 600))
        let size = try #require(pixelSize(of: jpeg))
        #expect(size.height <= 300)
    }

    @Test func garbageDataReturnsNil() async {
        #expect(await ImageDownscaler.jpegData(from: Data("not an image".utf8)) == nil)
    }
}
