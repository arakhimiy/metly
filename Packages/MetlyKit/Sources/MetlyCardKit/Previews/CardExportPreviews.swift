import MetlyCore
import PDFKit
import SwiftUI

/// Renders every export format once so they can be eyeballed in the canvas.
private struct ExportPreview: View {
    let design: CardDesign
    @State private var png: UIImage?
    @State private var lockScreen: UIImage?
    @State private var pdfSingle: UIImage?
    @State private var pdfSheet: UIImage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ExportPreviewImage(title: "PNG 2× (2040 × 1320)", image: png)
                ExportPreviewImage(title: "PDF · single card (bleed + crop marks)", image: pdfSingle)
                ExportPreviewImage(title: "PDF · A4 10-up", image: pdfSheet)
                ExportPreviewImage(title: "Lock Screen · iPhone 16 Pro", image: lockScreen)
            }
            .padding()
        }
        .task { render() }
    }

    private func render() {
        let content = CardFaceContent.sample
        png = CardExporter.pngImage(design: design, content: content, scale: 2)
        lockScreen = CardExporter.lockScreenWallpaper(design: design, content: content, device: .iPhone16Pro)
        pdfSingle = CardExporter.pdfSingle(design: design, content: content).flatMap(Self.firstPageImage)
        pdfSheet = CardExporter.pdfSheetA4(design: design, content: content).flatMap(Self.firstPageImage)
    }

    private static func firstPageImage(_ data: Data) -> UIImage? {
        guard let page = PDFDocument(data: data)?.page(at: 0) else { return nil }
        return page.thumbnail(of: CGSize(width: 900, height: 900), for: .mediaBox)
    }
}

private struct ExportPreviewImage: View {
    let title: String
    let image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 420)
                    .border(.quaternary)
            } else {
                ProgressView()
            }
        }
    }
}

#Preview("Exports · Split / Ocean dark") {
    ExportPreview(design: CardDesign(template: .split, palette: .ocean, appearance: .dark))
}

#Preview("Exports · Gradient / Ember light") {
    ExportPreview(design: CardDesign(template: .gradient, palette: .ember, appearance: .light))
}
