import CoreGraphics
import Testing
@testable import FeatureScan

@Suite("Paper crop")
struct PaperCropTests {
    // A 402×874 screen showing a 3024×4032 photo (aspect fill: the photo's sides are cut off).
    let preview = CGRect(x: 0, y: 0, width: 402, height: 874)
    let photo = CGSize(width: 3024, height: 4032)

    @Test func guideMapsIntoThePhotoWithAMargin() throws {
        let guide = CGRect(x: 40, y: 300, width: 322, height: 203)
        let region = try #require(PaperCrop.region(guide: guide, preview: preview, photoSize: photo, margin: 0))
        let scale = 874.0 / 4032.0
        let left = (3024 * scale - 402) / 2
        #expect(abs(region.minX - (40 + left) / scale) <= 1)
        #expect(abs(region.minY - 300 / scale) <= 1)
        #expect(abs(region.width - 322 / scale) <= 1)
    }

    @Test func marginGrowsTheRegionButStaysInsideThePhoto() throws {
        let guide = CGRect(x: 0, y: 0, width: 402, height: 874)
        let region = try #require(PaperCrop.region(guide: guide, preview: preview, photoSize: photo))
        #expect(CGRect(origin: .zero, size: photo).contains(region))
    }

    @Test func nothingWithoutAGuide() {
        #expect(PaperCrop.region(guide: .zero, preview: preview, photoSize: photo) == nil)
    }
}
