import CoreGraphics
import Foundation

/// One line of text read from a business card (Vision or VisionKit live text).
nonisolated struct OCRLine: Equatable, Sendable {
    var text: String
    /// Recognition confidence 0…1.
    var confidence: Double
    /// Text height relative to the image (0…1). 0 = unknown.
    var height: Double
    /// Where the line sits on the card: normalised 0…1, top-left origin. nil = unknown (live text, tests).
    var frame: CGRect?

    init(_ text: String, confidence: Double = 1, height: Double = 0, frame: CGRect? = nil) {
        self.text = text
        self.confidence = confidence
        self.height = height > 0 ? height : (frame?.height ?? 0)
        self.frame = frame
    }
}
