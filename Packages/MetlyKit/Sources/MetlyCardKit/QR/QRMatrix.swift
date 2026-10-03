import Foundation

/// The dark/light modules of a QR symbol, without quiet zone. Row-major, origin top-left.
public struct QRMatrix: Hashable, Sendable {
    /// Modules per side (21, 25, 29, … = 17 + 4 × version).
    public let size: Int
    let modules: [Bool]

    public init(size: Int, modules: [Bool]) {
        precondition(modules.count == size * size, "QRMatrix needs size² modules")
        self.size = size
        self.modules = modules
    }

    public subscript(x: Int, y: Int) -> Bool {
        guard x >= 0, y >= 0, x < size, y < size else { return false }
        return modules[y * size + x]
    }

    /// QR version (1…40).
    public var version: Int { (size - 17) / 4 }

    /// Whether a 7×7 finder pattern starts at (x, y).
    func hasFinderPattern(atX x: Int, y: Int) -> Bool {
        for dy in 0..<7 {
            for dx in 0..<7 {
                let ring = max(abs(dx - 3), abs(dy - 3))   // 3 = outer border, 2 = light ring, ≤1 = core
                if self[x + dx, y + dy] != (ring != 2) { return false }
            }
        }
        return true
    }

    /// Top-left, top-right and bottom-left finder patterns present (correct orientation).
    var isUpright: Bool {
        hasFinderPattern(atX: 0, y: 0) && hasFinderPattern(atX: size - 7, y: 0) && hasFinderPattern(atX: 0, y: size - 7)
    }

    func flippedVertically() -> QRMatrix {
        var flipped: [Bool] = []
        flipped.reserveCapacity(modules.count)
        for y in (0..<size).reversed() {
            flipped += modules[(y * size)..<((y + 1) * size)]
        }
        return QRMatrix(size: size, modules: flipped)
    }

    /// Horizontal runs of dark modules per row — used to build seam-free vector paths.
    var darkRuns: [(y: Int, x: Int, length: Int)] {
        var runs: [(Int, Int, Int)] = []
        for y in 0..<size {
            var x = 0
            while x < size {
                guard self[x, y] else { x += 1; continue }
                let start = x
                while x < size, self[x, y] { x += 1 }
                runs.append((y, start, x - start))
            }
        }
        return runs
    }
}
