import MetlyCore
import SwiftUI

/// Renders card exports for CARD_EXPORT (SPEC §2.5.25). Returns data/images only — no UI.
///
/// Pass `card.faceContent(profile:audience: .public)` — every export can leave the device.
@MainActor
public enum CardExporter {
    /// 1× PNG size in pixels (85 : 55); 2× = 2040 × 1320, 3× = 3060 × 1980.
    public static let pngBaseSize = CGSize(width: 1020, height: 660)

    public enum LockScreenDevice: String, CaseIterable, Identifiable, Sendable {
        case iPhone16Pro, iPhoneSE

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .iPhone16Pro: "iPhone 16 Pro"
            case .iPhoneSE: "iPhone SE"
            }
        }

        /// Wallpaper size in pixels.
        public var pixelSize: CGSize {
            switch self {
            case .iPhone16Pro: CGSize(width: 1206, height: 2622)
            case .iPhoneSE: CGSize(width: 750, height: 1334)
            }
        }
    }

    // MARK: PNG

    /// Card face as an image of `pngBaseSize × scale` pixels (scale 1, 2 or 3).
    /// Rounded corners are transparent; pass `roundedCorners: false` for a square, opaque image.
    public static func pngImage(design: CardDesign, content: CardFaceContent, scale: CGFloat = 2,
                                roundedCorners: Bool = true) -> UIImage? {
        let canvas = CardFaceCanvas(design: design, content: content, width: pngBaseSize.width,
                                    corners: roundedCorners ? .rounded : .square)
        let renderer = ImageRenderer(content: canvas)
        renderer.proposedSize = ProposedViewSize(pngBaseSize)
        renderer.scale = max(scale, 1)
        renderer.isOpaque = !roundedCorners
        return renderer.uiImage
    }

    public static func pngData(design: CardDesign, content: CardFaceContent, scale: CGFloat = 2,
                               roundedCorners: Bool = true) -> Data? {
        pngImage(design: design, content: content, scale: scale, roundedCorners: roundedCorners)?.pngData()
    }

    // MARK: PDF

    /// One card: 85 × 55 mm trim, 3 mm bleed, crop marks (page 105 × 75 mm, TrimBox/BleedBox set). Vector.
    public static func pdfSingle(design: CardDesign, content: CardFaceContent) -> Data? {
        renderPDF(layout: .single(), design: design, content: content)
    }

    /// A4 sheet with 10 cards (2 × 5, butted) and crop marks, for a print shop. Vector.
    public static func pdfSheetA4(design: CardDesign, content: CardFaceContent) -> Data? {
        renderPDF(layout: .sheetA4(), design: design, content: content)
    }

    // MARK: Lock Screen

    /// Wallpaper of `size` pixels: palette gradient, large QR (legible below the clock) and the card face.
    public static func lockScreenWallpaper(design: CardDesign, content: CardFaceContent, size: CGSize) -> UIImage? {
        let renderer = ImageRenderer(content: LockScreenWallpaperView(design: design, content: content, size: size))
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 1
        renderer.isOpaque = true
        return renderer.uiImage
    }

    public static func lockScreenWallpaper(design: CardDesign, content: CardFaceContent,
                                           device: LockScreenDevice) -> UIImage? {
        lockScreenWallpaper(design: design, content: content, size: device.pixelSize)
    }

    // MARK: - Private

    private static func renderPDF(layout: CardPrintLayout, design: CardDesign, content: CardFaceContent) -> Data? {
        let bleed = CardPrintLayout.bleed
        let canvas = CardFaceCanvas(design: design, content: content, width: CardPrintLayout.trimSize.width,
                                    bleed: bleed, corners: .square)
        let renderer = ImageRenderer(content: canvas)
        renderer.proposedSize = ProposedViewSize(width: CardPrintLayout.trimSize.width + 2 * bleed,
                                                 height: CardPrintLayout.trimSize.height + 2 * bleed)

        let data = NSMutableData()
        var mediaBox = CGRect(origin: .zero, size: layout.pageSize)
        let info: [CFString: Any] = [
            kCGPDFContextTitle: "\(content.fullName), Business Card",
            kCGPDFContextCreator: Brand.appName,
        ]
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let pdf = CGContext(consumer: consumer, mediaBox: &mediaBox, info as CFDictionary)
        else { return nil }

        var pageInfo: [CFString: Any] = [kCGPDFContextMediaBox: boxData(mediaBox)]
        if let trim = layout.trimBox { pageInfo[kCGPDFContextTrimBox] = boxData(trim) }
        if let bleedBox = layout.bleedBox { pageInfo[kCGPDFContextBleedBox] = boxData(bleedBox) }

        var rendered = false
        renderer.render { _, draw in
            pdf.beginPDFPage(pageInfo as CFDictionary)
            // Opaque white paper, so crop marks show in viewers that render transparency as black.
            pdf.setFillColor(CGColor(gray: 1, alpha: 1))
            pdf.fill(mediaBox)
            for placement in layout.placements {
                pdf.saveGState()
                pdf.clip(to: placement.clip)
                pdf.translateBy(x: placement.trim.minX - bleed, y: placement.trim.minY - bleed)
                draw(pdf)
                pdf.restoreGState()
            }
            drawCropMarks(layout.marks, in: pdf)
            pdf.endPDFPage()
            rendered = true
        }
        pdf.closePDF()
        return rendered ? data as Data : nil
    }

    private static func drawCropMarks(_ marks: [CardPrintLayout.Mark], in context: CGContext) {
        context.saveGState()
        context.setStrokeColor(CGColor(gray: 0, alpha: 1))
        context.setLineWidth(0.25)
        for mark in marks {
            context.move(to: mark.from)
            context.addLine(to: mark.to)
        }
        context.strokePath()
        context.restoreGState()
    }

    private static func boxData(_ rect: CGRect) -> CFData {
        var box = rect
        return Data(bytes: &box, count: MemoryLayout<CGRect>.size) as CFData
    }
}
