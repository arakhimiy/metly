import Foundation
import MetlyCardKit
import MetlyCore
import UniformTypeIdentifiers

/// One concrete file CARD_EXPORT can produce.
nonisolated enum ExportOutput: Hashable, Sendable {
    case png(scale: ExportScale, corners: ExportCorners)
    case pdf(ExportPDFLayout)
    case lockScreen(CardExporter.LockScreenDevice)

    var contentType: UTType {
        switch self {
        case .png, .lockScreen: .png
        case .pdf: .pdf
        }
    }

    /// Whether the result is an image that can go to Photos.
    var isPhoto: Bool { contentType == .png }

    /// The CARD_EXPORT tab that produces this output.
    var tab: CardExportTab {
        switch self {
        case .png: .image
        case .pdf: .pdf
        case .lockScreen: .lockScreen
        }
    }
}

/// PNG resolution (SPEC §2.5.25): 1× 1020 × 660 px, 2× Retina, 3× print-ready.
nonisolated enum ExportScale: Int, CaseIterable, Identifiable, Sendable {
    case x1 = 1, x2 = 2, x3 = 3

    var id: Int { rawValue }

    /// 1× size in pixels — mirrors `CardExporter.pngBaseSize` (85 : 55).
    static let baseSize = CGSize(width: 1020, height: 660)

    var title: String { "\(rawValue)×" }

    var pixelSize: CGSize {
        CGSize(width: Self.baseSize.width * CGFloat(rawValue), height: Self.baseSize.height * CGFloat(rawValue))
    }

    var subtitle: String {
        // Plain digits (String, not Int) so pixel sizes never get a thousands separator.
        let size = String(localized: "\(String(Int(pixelSize.width))) × \(String(Int(pixelSize.height))) px", bundle: .appStrings)
        return switch self {
        case .x1: size
        case .x2: String(localized: "\(size) · Retina", bundle: .appStrings)
        case .x3: String(localized: "\(size) · Print-ready", bundle: .appStrings)
        }
    }
}

nonisolated enum ExportCorners: String, CaseIterable, Identifiable, Sendable {
    case rounded, square

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rounded: String(localized: "Rounded", bundle: .appStrings)
        case .square: String(localized: "Square", bundle: .appStrings)
        }
    }

    var subtitle: String {
        switch self {
        case .rounded: String(localized: "Transparent corners, like the card in the app", bundle: .appStrings)
        case .square: String(localized: "Full rectangle, for print and slides", bundle: .appStrings)
        }
    }
}

nonisolated enum ExportPDFLayout: String, CaseIterable, Identifiable, Sendable {
    case single, sheetA4

    var id: String { rawValue }

    var title: String {
        switch self {
        case .single: String(localized: "Single Card", bundle: .appStrings)
        case .sheetA4: String(localized: "A4 Sheet", bundle: .appStrings)
        }
    }

    var subtitle: String {
        switch self {
        case .single: String(localized: "85 × 55 mm, 3 mm bleed, crop marks", bundle: .appStrings)
        case .sheetA4: String(localized: "10 cards up, for a print shop", bundle: .appStrings)
        }
    }
}

extension CardExporter.LockScreenDevice {
    nonisolated var subtitle: String { String(localized: "\(String(Int(pixelSize.width))) × \(String(Int(pixelSize.height))) px", bundle: .appStrings) }
}
