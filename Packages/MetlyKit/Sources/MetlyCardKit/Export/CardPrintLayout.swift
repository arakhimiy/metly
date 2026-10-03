import CoreGraphics

/// Print geometry for PDF exports, in PDF points (origin bottom-left).
///
/// - Single card: 85 × 55 mm trim, 3 mm bleed, crop marks in a slug around the bleed.
///   Page = trim + 2 × (bleed + 5 mm marks + 2 mm margin) = 105 × 75 mm; TrimBox/BleedBox are set.
/// - A4 sheet: 2 × 5 cards butted edge to edge (shared cut lines, the standard 10-up imposition),
///   centred on 210 × 297 mm, outer bleed on the sheet edges, crop marks on every cut line.
struct CardPrintLayout {
    struct Placement {
        /// Trim rectangle of one card.
        let trim: CGRect
        /// Area the card may paint into (trim + bleed on outer edges).
        let clip: CGRect
    }

    struct Mark: Equatable {
        let from: CGPoint
        let to: CGPoint
    }

    static func mm(_ value: CGFloat) -> CGFloat { value * 72 / 25.4 }

    static let trimSize = CGSize(width: mm(85), height: mm(55))
    static let bleed = mm(3)
    static let markLength = mm(5)
    static let slugMargin = mm(2)
    static let a4 = CGSize(width: mm(210), height: mm(297))

    let pageSize: CGSize
    let placements: [Placement]
    let marks: [Mark]
    /// Set for the single-card page (print-shop boxes).
    let trimBox: CGRect?
    let bleedBox: CGRect?

    static func single() -> CardPrintLayout {
        let outer = bleed + markLength + slugMargin
        let page = CGSize(width: trimSize.width + 2 * outer, height: trimSize.height + 2 * outer)
        let trim = CGRect(origin: CGPoint(x: outer, y: outer), size: trimSize)
        let bleedRect = trim.insetBy(dx: -bleed, dy: -bleed)
        let marks = cropMarks(cutsX: [trim.minX, trim.maxX], cutsY: [trim.minY, trim.maxY], around: trim)
        return CardPrintLayout(pageSize: page, placements: [Placement(trim: trim, clip: bleedRect)],
                               marks: marks, trimBox: trim, bleedBox: bleedRect)
    }

    static func sheetA4(columns: Int = 2, rows: Int = 5) -> CardPrintLayout {
        let grid = CGSize(width: trimSize.width * CGFloat(columns), height: trimSize.height * CGFloat(rows))
        let gridRect = CGRect(x: (a4.width - grid.width) / 2, y: (a4.height - grid.height) / 2,
                              width: grid.width, height: grid.height)
        var placements: [Placement] = []
        for row in 0..<rows {
            for column in 0..<columns {
                let trim = CGRect(x: gridRect.minX + CGFloat(column) * trimSize.width,
                                  y: gridRect.minY + CGFloat(row) * trimSize.height,
                                  width: trimSize.width, height: trimSize.height)
                // Bleed only where there is no neighbouring card.
                let left = column == 0 ? bleed : 0
                let right = column == columns - 1 ? bleed : 0
                let bottom = row == 0 ? bleed : 0
                let top = row == rows - 1 ? bleed : 0
                let clip = CGRect(x: trim.minX - left, y: trim.minY - bottom,
                                  width: trim.width + left + right, height: trim.height + bottom + top)
                placements.append(Placement(trim: trim, clip: clip))
            }
        }
        let cutsX = (0...columns).map { gridRect.minX + CGFloat($0) * trimSize.width }
        let cutsY = (0...rows).map { gridRect.minY + CGFloat($0) * trimSize.height }
        return CardPrintLayout(pageSize: a4, placements: placements,
                               marks: cropMarks(cutsX: cutsX, cutsY: cutsY, around: gridRect),
                               trimBox: nil, bleedBox: nil)
    }

    /// Marks on the extension of every cut line, starting outside the bleed.
    private static func cropMarks(cutsX: [CGFloat], cutsY: [CGFloat], around rect: CGRect) -> [Mark] {
        var marks: [Mark] = []
        for x in cutsX {
            marks.append(Mark(from: CGPoint(x: x, y: rect.maxY + bleed), to: CGPoint(x: x, y: rect.maxY + bleed + markLength)))
            marks.append(Mark(from: CGPoint(x: x, y: rect.minY - bleed), to: CGPoint(x: x, y: rect.minY - bleed - markLength)))
        }
        for y in cutsY {
            marks.append(Mark(from: CGPoint(x: rect.minX - bleed, y: y), to: CGPoint(x: rect.minX - bleed - markLength, y: y)))
            marks.append(Mark(from: CGPoint(x: rect.maxX + bleed, y: y), to: CGPoint(x: rect.maxX + bleed + markLength, y: y)))
        }
        return marks
    }
}
