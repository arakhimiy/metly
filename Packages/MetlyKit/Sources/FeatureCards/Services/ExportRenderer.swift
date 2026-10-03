import Foundation
import MetlyCardKit
import MetlyCore
import PDFKit
import UIKit

/// A rendered export, written to a temporary file so it can be shared, saved to Files or Photos.
struct RenderedExport: Identifiable {
    let id = UUID()
    let output: ExportOutput
    let fileURL: URL
    let data: Data
    /// What the preview area shows (the image itself, or the PDF's first page).
    let previewImage: UIImage?

    var fileName: String { fileURL.lastPathComponent }

    /// Deletes the temporary folder holding the file.
    func discard() {
        try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
    }
}

/// Renders `ExportOutput`s with `CardExporter`. Callers pass `.public` content (exports leave the device).
@MainActor
enum ExportRenderer {
    enum Failure: Error {
        case renderFailed
    }

    static func render(_ output: ExportOutput, design: CardDesign, content: CardFaceContent,
                       fileName: String) throws -> RenderedExport {
        let data: Data
        let preview: UIImage?
        switch output {
        case .png(let scale, let corners):
            guard let image = CardExporter.pngImage(design: design, content: content, scale: CGFloat(scale.rawValue),
                                                    roundedCorners: corners == .rounded),
                  let png = image.pngData()
            else { throw Failure.renderFailed }
            data = png
            preview = image
        case .pdf(let layout):
            let pdf = switch layout {
            case .single: CardExporter.pdfSingle(design: design, content: content)
            case .sheetA4: CardExporter.pdfSheetA4(design: design, content: content)
            }
            guard let pdf else { throw Failure.renderFailed }
            data = pdf
            preview = PDFDocument(data: pdf)?.page(at: 0)?.thumbnail(of: CGSize(width: 900, height: 900), for: .mediaBox)
        case .lockScreen(let device):
            guard let image = CardExporter.lockScreenWallpaper(design: design, content: content, device: device),
                  let png = image.pngData()
            else { throw Failure.renderFailed }
            data = png
            preview = image
        }

        let folder = URL.temporaryDirectory.appending(path: "CardExports/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let fileURL = folder.appending(path: fileName, directoryHint: .notDirectory)
        try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        return RenderedExport(output: output, fileURL: fileURL, data: data, previewImage: preview)
    }
}
