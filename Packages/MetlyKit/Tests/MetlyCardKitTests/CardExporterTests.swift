import CoreGraphics
import Foundation
import MetlyCore
import Testing
import UIKit
@testable import MetlyCardKit

@MainActor
@Suite("CardExporter")
struct CardExporterTests {
    private let design = CardDesign(template: .modern, palette: .ink, appearance: .dark)

    private func mm(_ value: CGFloat) -> CGFloat { value * 72 / 25.4 }

    private func firstPage(_ data: Data) throws -> CGPDFPage {
        let provider = try #require(CGDataProvider(data: data as CFData))
        let document = try #require(CGPDFDocument(provider))
        #expect(document.numberOfPages == 1)
        return try #require(document.page(at: 1))
    }

    @Test(arguments: [1, 2, 3])
    func pngHasExactPixelSize(_ scale: Int) throws {
        let data = try #require(CardExporter.pngData(design: design, content: .sample, scale: CGFloat(scale)))
        let image = try #require(UIImage(data: data)?.cgImage)
        #expect(image.width == 1020 * scale)
        #expect(image.height == 660 * scale)
    }

    @Test func pngBaseSizeKeepsCardAspectRatio() {
        #expect(abs(CardExporter.pngBaseSize.width / CardExporter.pngBaseSize.height - CardFaceView.aspectRatio) < 0.001)
    }

    @Test func squarePNGIsOpaque() throws {
        let image = try #require(CardExporter.pngImage(design: design, content: .sample, scale: 1, roundedCorners: false)?.cgImage)
        #expect([.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo))
    }

    @Test func singlePDFHasTrimBleedAndSlug() throws {
        let page = try firstPage(try #require(CardExporter.pdfSingle(design: design, content: .sample)))
        let media = page.getBoxRect(.mediaBox)
        #expect(abs(media.width - mm(105)) < 0.01 && abs(media.height - mm(75)) < 0.01)
        let trim = page.getBoxRect(.trimBox)
        #expect(abs(trim.width - mm(85)) < 0.01 && abs(trim.height - mm(55)) < 0.01)
        let bleed = page.getBoxRect(.bleedBox)
        #expect(abs(bleed.width - mm(91)) < 0.01 && abs(bleed.height - mm(61)) < 0.01)
        #expect(abs(trim.midX - media.midX) < 0.01 && abs(trim.midY - media.midY) < 0.01)
    }

    @Test func a4SheetPageSize() throws {
        let page = try firstPage(try #require(CardExporter.pdfSheetA4(design: design, content: .sample)))
        let media = page.getBoxRect(.mediaBox)
        #expect(abs(media.width - 595.28) < 0.01 && abs(media.height - 841.89) < 0.01)
    }

    @Test func a4LayoutIsTenButtedCardsWithMarksOnEveryCut() {
        let layout = CardPrintLayout.sheetA4()
        #expect(layout.placements.count == 10)
        #expect(layout.marks.count == 3 * 2 + 6 * 2)
        let union = layout.placements.map(\.trim).reduce(CGRect.null) { $0.union($1) }
        #expect(abs(union.width - mm(170)) < 0.01 && abs(union.height - mm(275)) < 0.01)
        #expect(abs(union.midX - mm(105)) < 0.01 && abs(union.midY - mm(148.5)) < 0.01)
        // Marks stay outside the bleed and on the page.
        let bleedArea = union.insetBy(dx: -mm(3), dy: -mm(3))
        let page = CGRect(origin: .zero, size: layout.pageSize)
        for mark in layout.marks {
            #expect(page.contains(mark.from) && page.contains(mark.to))
            #expect(!bleedArea.insetBy(dx: 0.01, dy: 0.01).contains(CGPoint(x: (mark.from.x + mark.to.x) / 2,
                                                                          y: (mark.from.y + mark.to.y) / 2)))
        }
    }

    @Test(arguments: CardExporter.LockScreenDevice.allCases)
    func lockScreenWallpaperHasDeviceSize(_ device: CardExporter.LockScreenDevice) throws {
        let image = try #require(CardExporter.lockScreenWallpaper(design: design, content: .sample, device: device))
        let cgImage = try #require(image.cgImage)
        #expect(CGFloat(cgImage.width) == device.pixelSize.width)
        #expect(CGFloat(cgImage.height) == device.pixelSize.height)
    }

    @Test func lockScreenLayoutFitsBetweenClockAndBottomInset() {
        for device in CardExporter.LockScreenDevice.allCases {
            let size = device.pixelSize
            let layout = LockScreenLayout(size: size)
            let bottom = layout.top + layout.qrSide + layout.captionGap + layout.captionSize * 1.3 + layout.cardGap
                + layout.cardWidth / CardFaceView.aspectRatio
            #expect(bottom <= size.height * 0.9 + 0.5)
            #expect(layout.qrSide >= size.width * 0.4)
        }
    }
}
