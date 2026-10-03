import Foundation

/// One line of text read from a business card (Vision or VisionKit live text).
nonisolated struct OCRLine: Hashable, Sendable {
    var text: String
    /// Recognition confidence 0…1.
    var confidence: Double
    /// Text height relative to the image (0…1). Bigger type is more likely the name. 0 = unknown.
    var height: Double

    init(_ text: String, confidence: Double = 1, height: Double = 0) {
        self.text = text
        self.confidence = confidence
        self.height = height
    }
}
