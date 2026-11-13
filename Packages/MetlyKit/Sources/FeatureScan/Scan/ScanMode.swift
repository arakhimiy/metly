import CoreGraphics

/// SCAN's camera modes. The tab opens in `.paper`, which also picks up Nameshake / vCard QR codes, so
/// the **QR Code | Paper Card** switch is hidden (`showsPicker`); `.qr` stays for previews and a return.
enum ScanMode: String, CaseIterable, Identifiable, Hashable {
    case qr, paper

    static let showsPicker = false

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qr: String(localized: "QR Code")
        case .paper: String(localized: "Paper Card")
        }
    }

    var hint: String {
        switch self {
        case .qr: String(localized: "Point at a Nameshake or vCard QR code")
        case .paper: String(localized: "Fit a business card in the frame, or point at a Nameshake QR")
        }
    }

    /// Viewfinder shape: square for QR, 85 : 55 business card for paper.
    var aspectRatio: CGFloat {
        switch self {
        case .qr: 1
        case .paper: 85.0 / 55.0
        }
    }

    var maxGuideWidth: CGFloat {
        switch self {
        case .qr: 250
        case .paper: 320
        }
    }
}
