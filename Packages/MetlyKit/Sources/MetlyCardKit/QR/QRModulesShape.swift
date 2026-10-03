import SwiftUI

/// Dark modules of a QR code as one vector path, laid out inside a square with a quiet zone.
/// A single path filled once has no anti-aliasing seams between adjacent modules (also in PDFs).
struct QRModulesShape: Shape {
    let matrix: QRMatrix
    var quietZone: Int = QRCodeGenerator.quietZone

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = side / CGFloat(matrix.size + 2 * quietZone)
        let origin = CGPoint(x: rect.midX - side / 2 + unit * CGFloat(quietZone),
                             y: rect.midY - side / 2 + unit * CGFloat(quietZone))
        var path = Path()
        for run in matrix.darkRuns {
            path.addRect(CGRect(x: origin.x + CGFloat(run.x) * unit, y: origin.y + CGFloat(run.y) * unit,
                                width: CGFloat(run.length) * unit, height: unit))
        }
        return path
    }
}

/// White plate behind a QR code; corner radius is a fraction of the side so it scales.
struct QRPlateShape: Shape {
    var cornerFraction: CGFloat

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let square = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        return Path(roundedRect: square, cornerRadius: side * cornerFraction, style: .continuous)
    }
}
