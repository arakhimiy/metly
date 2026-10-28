import CoreGraphics
import MetlyCore
import UIKit
import Vision

/// On-device OCR of a captured business card photo (Vision `RecognizeTextRequest`, iOS 18 API),
/// then `PaperCardRecognizer` (heuristics, plus Foundation Models when available).
/// Everything runs off the main actor; nothing leaves the device.
nonisolated enum PaperCardReader {
    /// Reads `photo` and parses it. When the still yields nothing usable, falls back to the live
    /// text VisionKit was showing (`liveLines`). The draft carries a small JPEG thumbnail for
    /// PAPER_REVIEW only — the photo isn't stored with the connection (SPEC §9 Q44).
    @concurrent
    static func read(_ photo: UIImage, liveLines: [OCRLine] = [], model: (any PaperCardLanguageModel)? = nil) async -> PaperScan {
        let ocrImage = upright(photo, maxDimension: 2400)
        let thumbnail = upright(photo, maxDimension: 900).jpegData(compressionQuality: 0.7)

        var lines: [OCRLine] = []
        if let data = ocrImage.jpegData(compressionQuality: 0.9) {
            lines = (try? await recognizeLines(in: data)) ?? []
        }
        var scan = await PaperCardRecognizer.recognize(lines, model: model)
        if !scan.draft.isReadable, !liveLines.isEmpty {
            scan = await PaperCardRecognizer.recognize(liveLines, model: model)
        }
        scan.draft.imageData = thumbnail
        return scan
    }

    /// Text lines top to bottom with confidence, relative type size and position.
    static func recognizeLines(in imageData: Data) async throws -> [OCRLine] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.automaticallyDetectsLanguage = true
        // Latin (English / Uzbek) and Cyrillic (Russian), limited to what this device supports.
        let wanted = [Locale.Language(identifier: "en-US"), Locale.Language(identifier: "ru-RU")]
        let supported = request.supportedRecognitionLanguages.map(\.maximalIdentifier)
        let languages = wanted.filter { supported.contains($0.maximalIdentifier) }
        if !languages.isEmpty { request.recognitionLanguages = languages }
        // Names, handles and emails aren't dictionary words — correction would "fix" them.
        request.usesLanguageCorrection = false

        let observations = try await request.perform(on: imageData)
        return observations
            .sorted { lhs, rhs in
                abs(lhs.topLeft.y - rhs.topLeft.y) > 0.01 ? lhs.topLeft.y > rhs.topLeft.y : lhs.topLeft.x < rhs.topLeft.x
            }
            .compactMap { observation in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                // Vision's origin is bottom-left; OCRLine frames are top-left.
                let minX = min(observation.topLeft.x, observation.bottomLeft.x)
                let maxX = max(observation.topRight.x, observation.bottomRight.x)
                let top = 1 - max(observation.topLeft.y, observation.topRight.y)
                let bottom = 1 - min(observation.bottomLeft.y, observation.bottomRight.y)
                let frame = CGRect(x: minX, y: top, width: max(0, maxX - minX), height: max(0, bottom - top))
                return OCRLine(candidate.string,
                               confidence: Double(candidate.confidence),
                               height: Double(abs(observation.topLeft.y - observation.bottomLeft.y)),
                               frame: frame)
            }
    }

    /// Redraws the photo upright (EXIF orientation applied), scaled to fit `maxDimension`.
    static func upright(_ image: UIImage, maxDimension: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return image }
        let scale = min(1, maxDimension / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
