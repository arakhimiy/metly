import CoreGraphics
import Foundation

/// Reading order and size / position words for OCR lines.
///
/// Vision returns lines top to bottom, so a two-column card (name and title on the left,
/// contacts on the right) comes back interleaved. When a clear vertical gutter splits the lines
/// into two columns, the left column is read first, then the right one; full-width lines above
/// or below the columns keep their place.
nonisolated enum PaperLayout {
    static func readingOrder(_ lines: [OCRLine]) -> [OCRLine] {
        let framed = lines.compactMap { line in line.frame.map { (line, $0) } }
        guard framed.count == lines.count, lines.count >= 4 else { return lines }
        let byRow = framed.sorted { lhs, rhs in
            abs(lhs.1.minY - rhs.1.minY) > min(lhs.1.height, rhs.1.height) / 2 ? lhs.1.minY < rhs.1.minY : lhs.1.minX < rhs.1.minX
        }
        guard let gutter = gutter(in: byRow.map(\.1)) else { return byRow.map(\.0) }

        let left = byRow.filter { $0.1.maxX <= gutter }
        let right = byRow.filter { $0.1.minX >= gutter }
        let spanning = byRow.filter { $0.1.minX < gutter && $0.1.maxX > gutter }
        let columnsTop = (left + right).map(\.1.minY).min() ?? 0
        let above = spanning.filter { $0.1.maxY <= columnsTop + 0.01 }
        let below = spanning.filter { $0.1.maxY > columnsTop + 0.01 }
        return (above + left + right + below).map(\.0)
    }

    /// An x position no column line crosses, with at least two lines on each side that share
    /// vertical space (side by side, not just stacked). Lines crossing it must sit above or
    /// below both columns (a full-width logo or address).
    static func gutter(in frames: [CGRect]) -> CGFloat? {
        let edges = Set(frames.map(\.maxX)).sorted()
        for edge in edges {
            let x = edge + 0.005
            let left = frames.filter { $0.maxX <= x }
            let right = frames.filter { $0.minX >= x }
            guard left.count >= 2, right.count >= 2 else { continue }
            let leftRange = (left.map(\.minY).min() ?? 0)...(left.map(\.maxY).max() ?? 0)
            let rightRange = (right.map(\.minY).min() ?? 0)...(right.map(\.maxY).max() ?? 0)
            guard leftRange.overlaps(rightRange) else { continue }
            let columnsTop = min(leftRange.lowerBound, rightRange.lowerBound)
            let columnsBottom = max(leftRange.upperBound, rightRange.upperBound)
            let crossing = frames.filter { $0.minX < x && $0.maxX > x }
            let crossingOutside = crossing.allSatisfy { $0.maxY <= columnsTop + 0.01 || $0.minY >= columnsBottom - 0.01 }
            if crossingOutside { return x }
        }
        return nil
    }

    // MARK: Descriptions (Foundation Models prompt)

    enum Size: String, Sendable {
        case largest = "largest text"
        case large = "large text"
        case medium = "medium text"
        case small = "small text"
    }

    static func size(of line: OCRLine, maxHeight: Double) -> Size? {
        guard line.height > 0, maxHeight > 0 else { return nil }
        let ratio = line.height / maxHeight
        if ratio >= 0.9 { return .largest }
        if ratio >= 0.65 { return .large }
        if ratio >= 0.4 { return .medium }
        return .small
    }

    /// "top left", "middle", "bottom right"… (nil without geometry).
    static func position(of line: OCRLine) -> String? {
        guard let frame = line.frame else { return nil }
        let vertical = frame.midY < 0.34 ? "top" : (frame.midY > 0.66 ? "bottom" : "middle")
        let horizontal = frame.midX < 0.4 ? "left" : (frame.midX > 0.6 ? "right" : "")
        return horizontal.isEmpty ? vertical : "\(vertical) \(horizontal)"
    }
}
